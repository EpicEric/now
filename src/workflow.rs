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
    collections::{BTreeSet, HashMap, HashSet},
    io::Write,
    num::NonZeroUsize,
    path::PathBuf,
    pin::Pin,
    process::Command,
    time::Duration,
};

use color_eyre::Section;
use futures::stream::FuturesUnordered;
use petgraph::{
    acyclic::Acyclic, algo::Cycle, matrix_graph::NodeIndex, stable_graph::StableDiGraph,
    visit::EdgeRef,
};
use serde::{Deserialize, Serialize};
use smol::{channel::Receiver, stream::StreamExt};
use tracing::{debug, info, instrument, warn};

use crate::{
    builder::{NowBuilder, local::LocalBuilder},
    environment::{EVAL_ID, NowEnvironment},
    job::{JobError, JobResult},
    serde::now_job_timeout,
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
    pub(crate) timeout: Option<humantime::Duration>,
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

impl WorkflowSource {
    pub(crate) fn nix_expression(&self) -> color_eyre::Result<String> {
        match self {
            WorkflowSource::Path(path) => {
                debug_assert!(path.is_absolute());
                let workflow_str = path
                    .to_str()
                    .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
                Ok(format!("(/. + {})", serde_json::to_string(&workflow_str)?))
            }
            WorkflowSource::Flake { path, attribute } => {
                Ok(format!("(builtins.getFlake \"{path}\").{attribute}"))
            }
        }
    }
}

impl From<&WorkflowSource> for String {
    fn from(value: &WorkflowSource) -> Self {
        match value {
            WorkflowSource::Path(path) => path.to_string_lossy().into_owned(),
            WorkflowSource::Flake { path, attribute } => format!("{}#{}", path, attribute),
        }
    }
}

pub(crate) struct NowWorkflowParams {
    pub(crate) workflow: WorkflowSource,
    pub(crate) ctrl_c: Receiver<()>,
    pub(crate) abort: bool,
    pub(crate) timeout: Option<Duration>,
    pub(crate) eval: bool,
    pub(crate) jobs: Option<Vec<String>>,
    pub(crate) all_jobs: bool,
    pub(crate) builders: Option<String>,
    pub(crate) cores: Option<NonZeroUsize>,
    pub(crate) local_only: bool,
    pub(crate) remote_only: bool,
    pub(crate) skip: bool,
}

impl NowEnvironment {
    #[instrument(
        skip_all,
        fields(
            workflow,
            abort,
            timeout,
            eval,
            jobs,
            all_jobs,
            builders,
            cores,
            local_only,
            remote_only,
            skip,
        )
    )]
    pub(crate) fn run_workflow(
        &mut self,
        NowWorkflowParams {
            workflow,
            ctrl_c,
            abort,
            timeout,
            eval,
            jobs,
            all_jobs,
            builders,
            cores,
            local_only,
            remote_only,
            skip,
        }: NowWorkflowParams,
    ) -> color_eyre::Result<()> {
        let builder = LocalBuilder::new(self, builders, local_only, remote_only, cores)?;
        let runner = builder.get_name();

        info!(
            runner,
            is_remote = false,
            "Evaluating workflow '{}'...",
            String::from(&workflow)
        );
        let workflow = self.evaluate_workflow(&workflow)?;
        if eval {
            println!("{}", serde_json::to_string(&workflow)?);
            return Ok(());
        } else {
            debug!("$duper.workflow" = duper::serde::ser::to_string_compact(&workflow)?);
        }

        if let Some(name) = workflow.name.as_ref() {
            info!(runner, is_remote = false, "Building tree for '{}'...", name);
        } else {
            info!(runner, is_remote = false, "Building tree for workflow...");
        }
        let NowWorkflowGraph {
            dag: mut tree,
            mut nodes,
        } = workflow.build_graph(jobs, all_jobs)?;
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
                            debug_assert!(tree.node_count() == 1);
                        }
                        DagNode::Job(_) => match nodes.remove(&node_index) {
                            Some(NowJobContainer::Single(job)) => {
                                futures.push(self.run_job_single(&builder, job, node_index))
                            }
                            Some(NowJobContainer::Multiple(job_vec)) => {
                                futures.push(self.run_jobs_multiple(&builder, job_vec, node_index));
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
                            Err(error @ JobError::NoMatchingBuilders { .. } | error @ JobError::NoMatchingRunners { .. }) if skip => {
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
                                    _ => unreachable!(),
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
                                    Ok(_) => Err(color_eyre::Report::from(error)),
                                    Err(report) => Err(report.error(error)),
                                }
                            }
                        }
                    } else {
                        if result.is_ok() {
                            info!(runner, is_remote = false, "Done.");
                        }
                        return result;
                    };
                }
            }
        });

        smol::future::block_on(executor.run(smol::future::or(workflow_task, abort_task)))
    }

    #[instrument(skip(self))]
    fn evaluate_workflow(&self, workflow: &WorkflowSource) -> color_eyre::Result<NowWorkflow> {
        let workflow_path = workflow.nix_expression()?;

        let nix_workflow = self.nix_project_source.as_ref().join("nix/workflow.nix");
        let nix_workflow_canonical = std::fs::canonicalize(&nix_workflow)?;
        let nix_workflow_str = nix_workflow_canonical
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
        let nix_workflow_path = format!("(/. + {})", serde_json::to_string(&nix_workflow_str)?);

        let vars_json = serde_json::to_string(&serde_json::to_string(&self.vars)?)?;
        let eval_id = serde_json::to_string(&*EVAL_ID)?;
        let nix_project_path = serde_json::to_string(self.nix_project_source.as_ref())?;

        let nix_command = format!(
            "(import {nix_workflow_path} {{ }}) {{ workflow = {workflow_path}; vars = builtins.fromJSON {vars_json}; evalId = {eval_id}; gcrootDir = {nix_project_path}; }}"
        );

        let mut command = Command::new("nix");
        command.env("NIXPKGS_ALLOW_UNSUPPORTED_SYSTEM", "1").args([
            "--extra-experimental-features",
            "nix-command flakes",
            "eval",
            "--impure",
            "--json",
            "--keep-derivations",
        ]);
        let output = command.arg("--expr").arg(nix_command).output()?;

        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!("Failed to evaluate workflow"));
        }

        Ok(serde_json::from_slice(&output.stdout)?)
    }
}

#[derive(Debug, Serialize)]
enum DagNode {
    Root,
    Job(String),
}

struct NowWorkflowGraph {
    dag: Acyclic<StableDiGraph<DagNode, ()>>,
    nodes: HashMap<NodeIndex<u32>, NowJobContainer>,
}

impl NowWorkflow {
    #[instrument(skip(self))]
    fn build_graph(
        self,
        target_jobs: Option<Vec<String>>,
        all_jobs: bool,
    ) -> color_eyre::Result<NowWorkflowGraph> {
        if self.jobs.is_empty() {
            return Err(color_eyre::eyre::eyre!("No jobs in workflow"));
        }

        let mut graph = StableDiGraph::new();
        let root = graph.add_node(DagNode::Root);

        let mut nodes: HashMap<NodeIndex<u32>, NowJobContainer> = HashMap::new();
        let mut graph_nodes: HashMap<String, NodeIndex<u32>> = HashMap::new();
        let mut edges: HashMap<String, HashSet<String>> = HashMap::new();

        let mut joined_jobs = String::new();
        for (job_id, job) in self.jobs.into_iter() {
            if !joined_jobs.is_empty() {
                joined_jobs.push_str(", ");
            }
            joined_jobs.push_str(&job_id);
            match job {
                NowJobContainer::Single(job) => {
                    for need in job.needs.iter().flatten() {
                        edges
                            .entry(job_id.clone())
                            .or_default()
                            .insert(need.clone());
                    }
                    let node = graph.add_node(DagNode::Job(job_id.clone()));
                    nodes.insert(node, NowJobContainer::Single(job));
                    graph_nodes.insert(job_id, node);
                    graph.add_edge(node, root, ());
                }
                NowJobContainer::Multiple(job_vec) => {
                    for need in job_vec.iter().flat_map(|job| job.needs.iter().flatten()) {
                        edges
                            .entry(job_id.clone())
                            .or_default()
                            .insert(need.clone());
                    }
                    let node = graph.add_node(DagNode::Job(job_id.clone()));
                    nodes.insert(node, NowJobContainer::Multiple(job_vec));
                    graph_nodes.insert(job_id, node);
                    graph.add_edge(node, root, ());
                }
            }
        }

        for (from, to) in edges {
            for edge in to {
                graph.add_edge(
                    *graph_nodes
                        .get(&edge)
                        .ok_or_else(|| color_eyre::eyre::eyre!("Unknown node {}", edge))?,
                    *graph_nodes
                        .get(&from)
                        .ok_or_else(|| color_eyre::eyre::eyre!("Unknown node {}", from))?,
                    (),
                );
            }
        }

        // Prune non-target jobs
        let jobs = if all_jobs {
            None
        } else if let Some(target_jobs) = target_jobs
            && !target_jobs.is_empty()
        {
            Some(target_jobs)
        } else if let Some(default_jobs) = self.default.as_ref()
            && !default_jobs.is_empty()
        {
            Some(default_jobs.clone())
        } else {
            return Err(color_eyre::eyre::eyre!(
                "No job specified. Available options: {joined_jobs}"
            ));
        };
        if let Some(target_jobs) = jobs {
            let job_nodes = target_jobs
                .iter()
                .map(|job_id| {
                    graph_nodes
                        .get(job_id)
                        .copied()
                        .ok_or_else(|| color_eyre::eyre::eyre!("Unknown job '{job_id}'"))
                })
                .collect::<color_eyre::Result<HashSet<NodeIndex<u32>>>>()?;

            // Collect the set of nodes to keep
            let mut keep: HashSet<NodeIndex<u32>> = HashSet::new();
            let mut stack: Vec<NodeIndex<u32>> = job_nodes.iter().copied().collect();
            while let Some(node) = stack.pop() {
                if !keep.insert(node) {
                    continue;
                }
                for dep in graph.neighbors_directed(node, petgraph::Direction::Incoming) {
                    if dep != root && !keep.contains(&dep) {
                        stack.push(dep);
                    }
                }
            }

            graph.retain_nodes(|_, node| node == root || keep.contains(&node));
        }

        let dag = graph.try_into().map_err(|cycle: Cycle<_>| {
            color_eyre::eyre::eyre!(
                "Cycle detected on '{}'",
                graph_nodes
                    .iter()
                    .find(|(_, value)| **value == cycle.node_id())
                    .map(|(key, _)| key.clone())
                    .unwrap_or("unknown".into())
            )
        })?;

        Ok(NowWorkflowGraph { dag, nodes })
    }
}
