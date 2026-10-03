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

use std::path::{Path, PathBuf};

use color_eyre::eyre::OptionExt;
use tracing::{debug, level_filters::LevelFilter};
use tracing_duper::DuperLayer;
use tracing_subscriber::{EnvFilter, Layer, layer::SubscriberExt, util::SubscriberInitExt};

use crate::{
    command::Command,
    environment::NowEnvironment,
    subscriber::NowSubscriberLayer,
    workflow::{NowJobsToRun, NowRunMode, NowWorkflowParams, WorkflowSource},
};

mod builder;
mod command;
mod environment;
mod graph;
mod job;
mod project;
mod secret;
mod serde;
mod setup;
mod subscriber;
mod utils;
mod workflow;

fn find_workflow(
    workflow: Option<PathBuf>,
    flake: Option<String>,
) -> color_eyre::Result<WorkflowSource> {
    if let Some(workflow) = workflow {
        if workflow.is_dir() {
            let now_path = workflow.join("now.nix");
            if now_path.exists() && !now_path.is_dir() {
                Ok(WorkflowSource::Path(now_path.canonicalize()?))
            } else {
                Err(color_eyre::eyre::eyre!(
                    "Workflow 'now.nix' not found in directory '{}'",
                    workflow.canonicalize()?.to_string_lossy()
                ))
            }
        } else if !workflow.exists() {
            Err(color_eyre::eyre::eyre!(
                "Workflow '{}' not found",
                workflow.to_string_lossy()
            ))
        } else {
            Ok(WorkflowSource::Path(workflow.canonicalize()?))
        }
    } else if let Some(flake) = flake {
        let (path, attribute) = flake.trim().split_once('#').unwrap_or((&flake, "now"));

        // Validate that each segment is between double-quotes, isn't empty, or doesn't have invalid characters
        let mut quoted = false;
        let mut attribute_chars = attribute.chars().enumerate().peekable();
        while let Some((i, char)) = attribute_chars.next() {
            match char {
                '"' => {
                    if quoted {
                        if attribute_chars.peek().is_some_and(|(_, next)| *next != '.') {
                            return Err(color_eyre::eyre::eyre!("Invalid quoted attribute"));
                        }
                        quoted = false;
                    } else if i > 0 {
                        return Err(color_eyre::eyre::eyre!("Invalid quoted attribute"));
                    } else {
                        quoted = true;
                    }
                }
                '.' => {
                    if !quoted {
                        let Some((_, next)) = attribute_chars.peek() else {
                            return Err(color_eyre::eyre::eyre!("Empty attribute name"));
                        };
                        if *next == '.' {
                            return Err(color_eyre::eyre::eyre!("Empty attribute name"));
                        }
                        if *next == '"' {
                            quoted = true;
                            let _ = attribute_chars.next();
                        }
                    }
                }
                '\\' if quoted => match attribute_chars.next() {
                    Some((_, '\\' | '"' | '$' | 'n' | 'r' | 't')) => {}
                    Some((_, c)) => {
                        return Err(color_eyre::eyre::eyre!("Invalid escape sequence: \\{}", c));
                    }
                    None => return Err(color_eyre::eyre::eyre!("Invalid escape")),
                },
                _ if quoted => {}
                'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' => {}
                _ => return Err(color_eyre::eyre::eyre!("Invalid character")),
            }
        }
        if quoted {
            return Err(color_eyre::eyre::eyre!("Unclosed quoted attribute"));
        }

        // If path is a filesystem path, convert to an absolute path
        let path = if path.contains(':') {
            path.to_string()
        } else {
            let path = Path::new(path).canonicalize()?;
            std::env::set_current_dir(if path.is_dir() {
                &path
            } else {
                path.parent().expect("flake has parent directory")
            })?;
            path.to_str()
                .ok_or_eyre("Flake path is not UTF-8")?
                .to_string()
        };

        Ok(WorkflowSource::Flake {
            path,
            attribute: attribute.to_string(),
        })
    } else {
        let canonical_cwdir = std::env::current_dir()?.canonicalize()?;
        let mut cwdir = Some(canonical_cwdir.as_path());
        while let Some(cwdir_path) = cwdir {
            let now_path = cwdir_path.join("now.nix");
            if now_path.exists() && !now_path.is_dir() {
                std::env::set_current_dir(cwdir_path)?;
                return Ok(WorkflowSource::Path(now_path));
            }
            cwdir = cwdir_path.parent();
        }
        Err(color_eyre::eyre::eyre!(
            "No workflow found recursively from '{}'",
            canonical_cwdir.to_string_lossy()
        ))
    }
}

fn main() -> color_eyre::Result<()> {
    let command = setup::setup()?;

    match command {
        Command::Init { workflow } => {
            let mut path = workflow.unwrap_or(PathBuf::from("."));
            if path.is_dir()
                || (!path.exists() && path.extension().is_none_or(|extension| extension != "nix"))
            {
                path.push("now.nix");
            }
            if path.exists() {
                return Err(color_eyre::eyre::eyre!(
                    "'{}' already exists",
                    path.to_string_lossy(),
                ));
            }
            if let Some(parent) = path.parent() {
                std::fs::create_dir_all(parent)?;
            }
            std::fs::write(&path, include_bytes!("init.nix"))?;
            println!(
                "'{}' has been initialized with a basic workflow",
                path.to_string_lossy(),
            );
        }

        Command::List {
            workflow,
            flake,
            env_file,
            cwdir,
            tree,
        } => {
            let workflow = find_workflow(workflow, flake)?;

            if let Some(cwdir) = cwdir {
                std::env::set_current_dir(cwdir)?;
            }

            let (sender, ctrl_c) = smol::channel::bounded(1);
            let _ = ctrlc::set_handler(move || {
                let _ = sender.try_send(());
            });

            let environment = smol::block_on(NowEnvironment::get(
                &workflow,
                ctrl_c,
                None,
                env_file.as_ref(),
                None,
            ))?;

            if tree {
                let workflow = smol::block_on(environment.evaluate_workflow(&workflow))?;
                let graph = workflow.build_graph()?;
                println!("{}", graph.to_dot());
            } else if let Some((width, _)) = terminal_size::terminal_size_of(std::io::stdout()) {
                print!(
                    "{}",
                    term_grid::Grid::new(
                        environment.jobs.keys().collect(),
                        term_grid::GridOptions {
                            direction: term_grid::Direction::TopToBottom,
                            filling: term_grid::Filling::Spaces(3),
                            width: usize::from(width.0),
                        },
                    )
                );
            } else {
                for job in environment.jobs.keys() {
                    println!("{job}");
                }
            }
        }

        Command::Eval {
            workflow,
            flake,
            env_file,
            cwdir,
        } => {
            let workflow = find_workflow(workflow, flake)?;

            if let Some(cwdir) = cwdir {
                std::env::set_current_dir(cwdir)?;
            }

            let (sender, ctrl_c) = smol::channel::bounded(1);
            ctrlc::set_handler(move || {
                let _ = sender.try_send(());
            })?;

            smol::block_on(async {
                let environment =
                    NowEnvironment::get(&workflow, ctrl_c, None, env_file.as_ref(), None).await?;
                let evaluated = environment.evaluate_workflow(&workflow).await?;
                println!("{}", serde_json::to_string(&evaluated)?);
                Ok::<(), color_eyre::Report>(())
            })?;
        }

        Command::Run {
            jobs,
            workflow,
            flake,
            dry_run,
            all_jobs,
            env_file,
            gcroot_dir,
            abort,
            timeout,
            cwdir,
            builders,
            cores,
            local_only,
            remote_only,
            skip,
            tracing,
        } => {
            let env_filter = EnvFilter::builder()
                .with_default_directive(LevelFilter::INFO.into())
                .from_env_lossy();
            if tracing.is_some() {
                tracing_subscriber::registry()
                    .with(
                        DuperLayer::default()
                            .with_span_timings(true)
                            .with_filter(env_filter),
                    )
                    .init();
            } else {
                tracing_subscriber::registry()
                    .with(NowSubscriberLayer::default().with_filter(env_filter))
                    .init();
            }

            let workflow = find_workflow(workflow, flake)?;

            if let Some(cwdir) = cwdir {
                debug!("Changing cwdir to '{}'...", cwdir.to_string_lossy());
                std::env::set_current_dir(cwdir)?;
            }

            let (sender, ctrl_c) = smol::channel::bounded(1);
            ctrlc::set_handler(move || {
                let _ = sender.try_send(());
            })?;

            let run_mode = if local_only {
                NowRunMode::LocalOnly
            } else if remote_only {
                NowRunMode::RemoteOnly
            } else {
                NowRunMode::All
            };

            let jobs = if let Some(jobs) = jobs {
                NowJobsToRun::Selected(jobs)
            } else if all_jobs {
                NowJobsToRun::All
            } else {
                NowJobsToRun::Default
            };

            smol::block_on::<color_eyre::Result<()>>(async {
                let mut environment = NowEnvironment::get(
                    &workflow,
                    ctrl_c.clone(),
                    tracing,
                    env_file.as_ref(),
                    gcroot_dir,
                )
                .await?;
                environment
                    .run_workflow(NowWorkflowParams {
                        workflow,
                        ctrl_c,
                        dry_run,
                        abort,
                        timeout: timeout.map(std::convert::Into::into),
                        jobs_to_run: jobs,
                        builders,
                        cores,
                        run_mode,
                        skip,
                    })
                    .await
            })?;
        }
    }
    Ok(())
}
