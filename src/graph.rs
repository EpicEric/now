use std::fmt::Display;

use ahash::{HashMap, HashMapExt, HashSet, HashSetExt};
use petgraph::{acyclic::Acyclic, algo::Cycle, dot, graph::NodeIndex, stable_graph::StableDiGraph};
use serde::Serialize;
use tracing::instrument;

use crate::workflow::{NowJobContainer, NowWorkflow};

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
}

impl NowWorkflowGraph {
    pub(crate) fn prune(
        &mut self,
        target_jobs: Option<Vec<String>>,
        all_jobs: bool,
    ) -> color_eyre::Result<()> {
        // Filter out non-target jobs
        let jobs = if all_jobs {
            None
        } else if let Some(target_jobs) = target_jobs
            && !target_jobs.is_empty()
        {
            Some(target_jobs)
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
            return Err(color_eyre::eyre::eyre!(
                "No job specified. Available options: {joined_jobs}"
            ));
        };
        if let Some(target_jobs) = jobs {
            let mut job_nodes: HashSet<NodeIndex<u32>> = HashSet::new();
            for job_glob in target_jobs {
                let glob = glob::Pattern::new(&job_glob)?;
                let mut matching_jobs = vec![];
                for (job_id, value) in self.graph_nodes.iter() {
                    if glob.matches(job_id) {
                        matching_jobs.push(*value);
                    }
                }
                if matching_jobs.is_empty() {
                    return Err(color_eyre::eyre::eyre!("No jobs matched '{job_glob}'"));
                } else {
                    job_nodes.extend(matching_jobs);
                }
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

        Ok(NowWorkflowGraph {
            dag,
            nodes,
            root,
            graph_nodes,
        })
    }
}
