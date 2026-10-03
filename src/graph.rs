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

use std::fmt::Display;

use ahash::{HashMap, HashMapExt, HashSet, HashSetExt};
use color_eyre::Section;
use petgraph::{acyclic::Acyclic, algo::Cycle, dot, graph::NodeIndex, stable_graph::StableDiGraph};
use serde::Serialize;
use tracing::instrument;

use crate::workflow::{NowJobContainer, NowJobsToRun, NowWorkflow};

#[derive(Debug, Clone, Serialize)]
pub(crate) enum DagNode {
    Root,
    Job(String),
}

impl Display for DagNode {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            DagNode::Root => "== root ==",
            DagNode::Job(job) => job,
        })
    }
}

pub(crate) struct NowWorkflowGraph {
    pub(crate) dag: Acyclic<StableDiGraph<DagNode, ()>>,
    pub(crate) nodes: HashMap<NodeIndex<u32>, NowJobContainer>,
    root: NodeIndex<u32>,
    graph_nodes: HashMap<String, NodeIndex<u32>>,
    default_jobs: Option<Vec<String>>,
}

impl NowWorkflowGraph {
    fn closest_matches(&self, needle: &str) -> Vec<&String> {
        let mut matches: Vec<&String> = self
            .dag
            .node_weights()
            .filter_map(|node| match node {
                DagNode::Job(text) if strsim::normalized_levenshtein(text, needle) >= 0.5 => {
                    Some(text)
                }
                DagNode::Job(_) | DagNode::Root => None,
            })
            .collect();
        matches.sort();
        matches
    }

    fn available_jobs(&self) -> String {
        let mut jobs: Vec<&String> = self
            .dag
            .node_weights()
            .filter_map(|node| match node {
                DagNode::Root => None,
                DagNode::Job(text) => Some(text),
            })
            .collect();
        jobs.sort();
        let mut joined_jobs = String::new();
        for job in jobs {
            if !joined_jobs.is_empty() {
                joined_jobs.push_str(", ");
            }
            joined_jobs.push_str(job);
        }
        joined_jobs
    }

    pub(crate) fn prune(&mut self, jobs: NowJobsToRun) -> color_eyre::Result<()> {
        // Filter out non-target jobs
        let jobs = match jobs {
            NowJobsToRun::All => None,
            NowJobsToRun::Selected(items) => {
                debug_assert!(!items.is_empty());
                Some(items)
            }
            NowJobsToRun::Default => {
                if let Some(default_jobs) = self.default_jobs.as_ref()
                    && !default_jobs.is_empty()
                {
                    Some(default_jobs.clone())
                } else {
                    let mut jobs: Vec<&String> = self
                        .dag
                        .node_weights()
                        .filter_map(|node| match node {
                            DagNode::Root => None,
                            DagNode::Job(text) => Some(text),
                        })
                        .collect();
                    jobs.sort();
                    let mut joined_jobs = String::new();
                    for job in jobs {
                        if !joined_jobs.is_empty() {
                            joined_jobs.push_str(", ");
                        }
                        joined_jobs.push_str(job);
                    }
                    return Err(color_eyre::eyre::eyre!("No default jobs in workflow").note(
                        format!(
                            "Specify a job directly. Available options: {}",
                            self.available_jobs(),
                        ),
                    ));
                }
            }
        };

        if let Some(target_jobs) = jobs {
            let mut job_nodes: HashSet<NodeIndex<u32>> = HashSet::new();
            for job_glob in target_jobs {
                let glob = glob::Pattern::new(&job_glob)?;
                let mut matching_jobs = vec![];
                for (job_id, value) in &self.graph_nodes {
                    if glob.matches(job_id) {
                        matching_jobs.push(*value);
                    }
                }
                if matching_jobs.is_empty() {
                    let mut error = color_eyre::eyre::eyre!("No jobs matched '{job_glob}'")
                        .note(format!("Available options: {}", self.available_jobs()));
                    for maybe_match in self.closest_matches(&job_glob) {
                        error = error.suggestion(format!("Did you mean '{maybe_match}'?"))
                    }
                    return Err(error);
                }
                job_nodes.extend(matching_jobs);
            }

            // Collect the set of nodes to keep
            let mut keep: HashSet<NodeIndex<u32>> = HashSet::new();
            keep.insert(self.root);
            let mut stack: Vec<NodeIndex<u32>> = job_nodes.iter().copied().collect();
            while let Some(node) = stack.pop() {
                if !keep.insert(node) {
                    continue;
                }
                for dep in self
                    .dag
                    .neighbors_directed(node, petgraph::Direction::Incoming)
                {
                    if dep != self.root && !keep.contains(&dep) {
                        stack.push(dep);
                    }
                }
            }

            let remove: Vec<NodeIndex<u32>> = self
                .dag
                .node_indices()
                .filter(|index| !keep.contains(index))
                .collect();
            for node in remove {
                self.dag.remove_node(node);
            }
        }

        Ok(())
    }

    pub(crate) fn to_dot(&self) -> String {
        let mut graph = self.dag.inner().clone();
        graph.remove_node(self.root);
        format!(
            "{:?}",
            dot::Dot::with_attr_getters(
                &graph,
                &[dot::Config::NodeNoLabel, dot::Config::EdgeNoLabel],
                &|_, _| String::new(),
                &|_, (_, node)| format!(r#"label = "{}""#, node.to_string().replace('"', r#"\""#)),
            )
        )
    }
}

impl NowWorkflow {
    #[instrument(skip(self))]
    pub(crate) fn build_graph(self) -> color_eyre::Result<NowWorkflowGraph> {
        if self.jobs.is_empty() {
            return Err(color_eyre::eyre::eyre!("No jobs in workflow"));
        }

        let mut graph = StableDiGraph::new();
        let root = graph.add_node(DagNode::Root);

        let mut nodes: HashMap<NodeIndex<u32>, NowJobContainer> = HashMap::new();
        let mut graph_nodes: HashMap<String, NodeIndex<u32>> = HashMap::new();
        let mut edges: HashMap<String, HashSet<String>> = HashMap::new();

        let mut joined_jobs = String::new();
        for (job_id, job) in self.jobs {
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

        let dag = graph.try_into().map_err(|cycle: Cycle<_>| {
            color_eyre::eyre::eyre!(
                "Cycle detected on '{}'",
                graph_nodes
                    .iter()
                    .find(|(_, value)| **value == cycle.node_id())
                    .map_or("unknown".into(), |(key, _)| key.clone())
            )
        })?;

        Ok(NowWorkflowGraph {
            dag,
            nodes,
            root,
            graph_nodes,
            default_jobs: self.default,
        })
    }
}
