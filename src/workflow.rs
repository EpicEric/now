// now: Nix-based distributed command runner
// Copyright (C) 2026 Eric Rodrigues Pires
//
// This program is free software: you can redistribute it and/or modify it under
// the terms of the GNU Affero General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
// more details.
//
// You should have received a copy of the GNU Affero General Public License along
// with this program. If not, see <https://www.gnu.org/licenses/>.

use std::{
    collections::BTreeSet,
    fmt::{Display, Write},
    num::NonZeroUsize,
    path::PathBuf,
    pin::Pin,
    process::Stdio,
    time::Duration,
};

use ahash::{HashMap, HashSet, HashSetExt};
use color_eyre::Section;
use futures::stream::FuturesUnordered;
use petgraph::{matrix_graph::NodeIndex, visit::EdgeRef};
use serde::{Deserialize, Serialize};
use smol::{channel::Receiver, process::Command, stream::StreamExt};
use tracing::{debug, info, instrument, warn};

use crate::{
    builder::{NowBuilder, local::LocalBuilder},
    environment::{NowEnvironment, eval_id},
    graph::{DagNode, NowWorkflowGraph},
    job::{JobError, JobResult},
    serde::now_job_timeout,
    utils::{parse_bool_from_bytes, wait_for_output, write_output_to_stderr},
};

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct NowWorkflow {
    pub(crate) name: Option<String>,
    pub(crate) default: Option<Vec<String>>,
    pub(crate) jobs: HashMap<String, NowJobContainer>,
}

#[derive(Debug)]
pub(crate) enum NowJobContainer {
    Single(NowJob),
    Multiple(Vec<NowJob>),
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub(crate) enum NowCheckout {
    None,
    Default,
    Clone,
    All,
    CloneAll,
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct NowJob {
    pub(crate) name: String,
    #[serde(rename = "buildSystem")]
    pub(crate) build_system: String,
    #[serde(rename = "hostSystem")]
    pub(crate) host_system: String,
    #[serde(rename = "requiredSystemFeatures")]
    pub(crate) required_system_features: HashSet<String>,
    pub(crate) checkout: NowCheckout,
    #[serde(with = "now_job_timeout")]
    pub(crate) timeout: Option<Duration>,
    pub(crate) strategy: Option<NowStrategy>,
    pub(crate) needs: Option<Vec<String>>,
    pub(crate) steps: Vec<NowStep>,
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct NowStrategy {
    #[serde(rename = "failFast")]
    pub(crate) fail_fast: bool,
}

#[derive(Clone, Debug)]
pub(crate) struct NowStep {
    pub(crate) name: String,
    pub(crate) run_drv: PathBuf,
    pub(crate) teardown_drv: Option<PathBuf>,
    pub(crate) env: HashMap<String, NowStepEnvVar>,
    pub(crate) output_var: Option<String>,
    pub(crate) upload_key: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(untagged)]
pub(crate) enum NowStepEnvVar {
    Plain(String),
    Secret(NowStepSecret),
    Download(NowStepDownload),
}

#[derive(Clone, Debug)]
pub(crate) struct NowStepSecret {
    pub(crate) secret_name: String,
}

#[derive(Clone, Debug)]
pub(crate) struct NowStepDownload {
    pub(crate) download_name: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub(crate) enum WorkflowSource {
    Path(PathBuf),
    Flake { path: String, attribute: String },
}

impl Display for WorkflowSource {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            WorkflowSource::Path(path_buf) => f.write_str(&path_buf.to_string_lossy()),
            WorkflowSource::Flake { path, attribute } => {
                f.write_str(path)?;
                f.write_char('#')?;
                f.write_str(attribute)
            }
        }
    }
}

impl WorkflowSource {
    pub(crate) fn nix_expression(&self) -> color_eyre::Result<String> {
        match self {
            WorkflowSource::Path(path) => {
                debug_assert!(path.is_absolute());
                let workflow_str = path
                    .to_str()
                    .ok_or_else(|| color_eyre::eyre::eyre!("Workflow path is not UTF-8"))?;
                Ok(format!("(/. + {})", serde_json::to_string(&workflow_str)?))
            }
            WorkflowSource::Flake { path, attribute } => {
                Ok(format!("(builtins.getFlake \"{path}\").{attribute}"))
            }
        }
    }

    pub(crate) fn nix_source_expression(&self) -> color_eyre::Result<String> {
        match self {
            WorkflowSource::Path(_) => self.nix_expression(),
            WorkflowSource::Flake { path, .. } => {
                Ok(format!("(builtins.getFlake \"{path}\").outPath"))
            }
        }
    }
}

impl From<&WorkflowSource> for String {
    fn from(value: &WorkflowSource) -> Self {
        match value {
            WorkflowSource::Path(path) => path.to_string_lossy().into_owned(),
            WorkflowSource::Flake { path, attribute } => format!("{path}#{attribute}"),
        }
    }
}

pub(crate) enum NowJobsToRun {
    Default,
    Selected(Vec<String>),
    All,
}

pub(crate) enum NowRunMode {
    All,
    LocalOnly,
    RemoteOnly,
}

pub(crate) struct NowWorkflowParams {
    pub(crate) workflow: WorkflowSource,
    pub(crate) ctrl_c: Receiver<()>,
    pub(crate) dry_run: bool,
    pub(crate) abort: bool,
    pub(crate) timeout: Option<Duration>,
    pub(crate) keep_alive: Option<Duration>,
    pub(crate) jobs_to_run: NowJobsToRun,
    pub(crate) builders: Option<String>,
    pub(crate) cores: Option<NonZeroUsize>,
    pub(crate) run_mode: NowRunMode,
    pub(crate) skip: bool,
}

impl NowEnvironment {
    #[instrument(
        skip_all,
        fields(
            workflow,
            abort,
            timeout,
            jobs,
            all_jobs,
            builders,
            cores,
            local_only,
            remote_only,
            skip,
        )
    )]
    pub(crate) async fn run_workflow(
        &mut self,
        NowWorkflowParams {
            workflow,
            ctrl_c,
            dry_run,
            abort,
            timeout,
            keep_alive,
            jobs_to_run,
            builders,
            cores,
            run_mode,
            skip,
        }: NowWorkflowParams,
    ) -> color_eyre::Result<()> {
        let builder = LocalBuilder::new(self, builders, run_mode, cores, keep_alive).await?;
        let runner = builder.get_name();

        info!(
            runner,
            is_remote = false,
            "Evaluating workflow '{}'...",
            String::from(&workflow)
        );
        let workflow = self.evaluate_workflow(&workflow).await?;
        debug!("$duper.workflow" = duper::serde::ser::to_string_compact(&workflow)?);

        if let Some(name) = workflow.name.as_ref() {
            info!(runner, is_remote = false, "Building tree for '{}'...", name);
        } else {
            info!(runner, is_remote = false, "Building tree for workflow...");
        }
        let mut graph = workflow.build_graph()?;
        graph.prune(jobs_to_run)?;
        let NowWorkflowGraph {
            dag: mut tree,
            mut nodes,
            ..
        } = graph;
        debug!("$duper.graph" = duper::serde::ser::to_string_compact(tree.inner())?);

        let executor = smol::LocalExecutor::new();

        let builder_ref = &builder;
        let abort_task = executor.spawn(async move {
            smol::future::race(
                async {
                    if ctrl_c.recv().await.is_ok() {
                        builder_ref.cancel_builders();
                    }
                },
                async {
                    if let Some(timeout) = timeout {
                        smol::Timer::after(timeout).await;
                        builder_ref.cancel_builders();
                    } else {
                        smol::future::pending::<()>().await;
                    }
                },
            )
            .await;
            smol::future::pending::<color_eyre::Result<()>>().await
        });

        let workflow_task = executor.spawn(async {
            let mut futures = FuturesUnordered::<Pin<Box<dyn Future<Output = JobResult>>>>::new();
            let mut result = Ok(());

            let mut current_nodes: HashSet<NodeIndex<u32>> = HashSet::new();
            for node in tree.nodes_iter() {
                if tree
                    .edges_directed(node, petgraph::Direction::Incoming)
                    .next()
                    .is_none()
                {
                    current_nodes.insert(node);
                }
            }
            debug_assert!(!current_nodes.is_empty());

            loop {
                for node_index in current_nodes {
                    let node_weight = &tree[node_index];
                    match node_weight {
                        DagNode::Root => {
                            debug_assert_eq!(tree.node_count(), 1);
                        }
                        DagNode::Job(_) => match nodes.remove(&node_index) {
                            Some(NowJobContainer::Single(job)) => {
                                futures.push(self.run_job_single(&builder, job, node_index, dry_run));
                            }
                            Some(NowJobContainer::Multiple(job_vec)) => {
                                futures.push(self.run_jobs_multiple(&builder, job_vec, node_index, dry_run));
                            }
                            None => (),
                        },
                    }
                }

                loop {
                    if let Some((node_index, future)) = futures.next().await {
                        match future {
                            Ok(()) => {
                                current_nodes = HashSet::new();
                                let possible_next_nodes: Vec<_> = tree
                                    .edges_directed(node_index, petgraph::Direction::Outgoing)
                                    .map(|edge| edge.target())
                                    .collect();
                                tree.remove_node(node_index);
                                for node in possible_next_nodes {
                                    if tree
                                        .edges_directed(node, petgraph::Direction::Incoming)
                                        .next()
                                        .is_none()
                                    {
                                        current_nodes.insert(node);
                                    }
                                }
                                break;
                            }
                            Err(error @
(JobError::NoMatchingBuilders { .. } | JobError::NoMatchingRunners { .. })) if skip => {
                                let skip_log = match error {
                                    JobError::NoMatchingBuilders {
                                        job_name,
                                        build_system,
                                        required_system_features,
                                    } => format!("No builders match for job '{job_name}' (buildSystem = {build_system}, requiredSystemFeatures = {required_system_features:?}); skipping."),
                                    JobError::NoMatchingRunners {
                                        job_name,
                                        host_system,
                                        required_system_features,
                                    } => format!("No runners match for job '{job_name}' (hostSystem = {host_system}, requiredSystemFeatures = {required_system_features:?}); skipping."),
                                    JobError::Other(_) => unreachable!(),
                                };
                                warn!(runner, is_remote = false, "{}", skip_log);
                                let mut nodes_to_skip: Vec<_> =
                                    vec![node_index].into_iter().collect();
                                while !nodes_to_skip.is_empty() {
                                    while let Some(node_index) = nodes_to_skip.pop() {
                                        let new_nodes_to_skip: Vec<_> = tree
                                            .edges_directed(
                                                node_index,
                                                petgraph::Direction::Outgoing,
                                            )
                                            .map(|edge| edge.target())
                                            .collect();
                                        match tree.remove_node(node_index) {
                                            Some(DagNode::Job(_)) => {
                                                match nodes.remove(&node_index) {
                                                    Some(NowJobContainer::Single(job)) => {
                                                        warn!(
                                                            runner,
                                                            is_remote = false,
                                                            "... also skipping dependent job '{}'.",
                                                            job.name
                                                        );
                                                    }
                                                    Some(NowJobContainer::Multiple(job_vec)) => {
                                                        let job_names: BTreeSet<_> = job_vec.iter().map(|job| &job.name).collect();
                                                        warn!(
                                                            runner,
                                                            is_remote = false,
                                                            "... also skipping dependent job set '{:?}'.",
                                                            job_names
                                                        );
                                                    }
                                                    None => (),
                                                }

                                            }
                                            Some(DagNode::Root) | None => {}
                                        }
                                        nodes_to_skip.extend(new_nodes_to_skip);
                                    }
                                }
                            }
                            Err(error) => {
                                if abort {
                                    builder.cancel_builders();
                                }
                                result = match result {
                                    Ok(()) => Err(color_eyre::Report::from(error)),
                                    Err(report) => Err(report.error(error)),
                                }
                            }
                        }
                    } else {
                        if result.is_ok() {
                            info!(runner, is_remote = false, "Done.");
                        }
                        return result;
                    }
                }
            }
        });

        executor
            .run(smol::future::or(workflow_task, abort_task))
            .await
    }

    #[instrument(skip(self))]
    pub(crate) async fn evaluate_workflow(
        &self,
        workflow: &WorkflowSource,
    ) -> color_eyre::Result<NowWorkflow> {
        let workflow_path = workflow.nix_expression()?;

        let nix_workflow = self.nix_project_source.as_ref().join("now/workflow.nix");
        let nix_workflow_canonical = smol::fs::canonicalize(&nix_workflow).await?;
        let nix_workflow_str = nix_workflow_canonical
            .to_str()
            .expect("project source path should be UTF-8");
        let nix_workflow_path = format!("(/. + {})", serde_json::to_string(&nix_workflow_str)?);

        let vars_json = serde_json::to_string(&serde_json::to_string(&self.vars)?)?;
        let eval_id = serde_json::to_string(eval_id())?;
        let with_local_step = option_env!("NOW_WITH_LOCAL_STEP").is_some_and(parse_bool_from_bytes);

        let nix_command = format!(
            "(import {nix_workflow_path} {{ \
                withLocalStep = {with_local_step}; \
            }}) {{ \
                workflow = {workflow_path}; \
                vars = builtins.fromJSON {vars_json}; \
                evalId = {eval_id}; \
            }}"
        );

        let mut command = Command::new("nix");
        command
            .env("NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM", "1")
            .args([
                "--extra-experimental-features",
                "nix-command flakes",
                "eval",
                "--impure",
                "--json",
                "--keep-derivations",
                "--expr",
            ])
            .arg(nix_command)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = command.spawn()?;
        let output = wait_for_output(&mut child, None).await?;
        if output.status.success() {
            Ok(serde_json::from_slice(&output.stdout)?)
        } else {
            write_output_to_stderr(&output)?;
            Err(color_eyre::eyre::eyre!(
                "Failed to evaluate workflow at {}",
                workflow
            ))
        }
    }
}
