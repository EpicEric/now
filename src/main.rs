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
    collections::HashSet,
    path::{Path, PathBuf},
};

use clap::{CommandFactory, Parser};
use clap_complete::{ArgValueCandidates, ArgValueCompleter, CompletionCandidate, PathCompleter};
use color_eyre::eyre::OptionExt;
use tracing::{debug, level_filters::LevelFilter};
use tracing_duper::DuperLayer;
use tracing_subscriber::{EnvFilter, Layer, layer::SubscriberExt, util::SubscriberInitExt};

use crate::{
    environment::NowEnvironment,
    subscriber::NowSubscriberLayer,
    workflow::{NowWorkflowParams, WorkflowSource},
};

mod builder;
mod environment;
mod job;
mod project;
mod secret;
mod serde;
mod subscriber;
mod utils;
mod workflow;

static LONG_ABOUT: &str = "now - Nix-based distributed command runner.

\x1b[1;4mExamples:\x1b[0m
  \x1b[2m# Initialize a basic workflow in ./now.nix\x1b[0m
  now init

  \x1b[2m# Load envvars from a dotenv file and run the default job(s)\x1b[0m
  now run --env-file .env

  \x1b[2m# Run the \"deploy\" job (and all dependencies) from the specified workflow,
  # and specify a remote builder for the run\x1b[0m
  now run deploy \\
    --builders \"ssh://mac aarch64-darwin\" \\
    --workflow .now/remote.nix

  \x1b[2m# Abort immediately on the first failing job,
  # and don't checkout the current directory\x1b[0m
  now run --abort --checkout none";

#[derive(Parser)]
#[command(name = "now", version, about, long_about = LONG_ABOUT)]
enum Command {
    /// Initialize a basic workflow.
    Init {
        /// Path to the workflow.
        workflow: Option<PathBuf>,
    },

    /// Run one or more jobs.
    Run {
        /// Jobs to target in this run.
        ///
        /// If unspecified, the default jobs of the workflow are run.
        ///
        /// Cannot be used together with the `--all-jobs` option.
        #[arg(
            value_name = "JOB",
            add = ArgValueCandidates::new(job_completer)
        )]
        jobs: Option<Vec<String>>,

        /// Path to the workflow.
        ///
        /// Cannot be used together with the `--flake` option.
        #[arg(
            short,
            long,
            value_name = "FILE",
            add = ArgValueCompleter::new(PathCompleter::any().filter(workflow_filter)),
        )]
        workflow: Option<PathBuf>,

        /// Path to the flake and an optional attribute (defaults to the `now` output).
        ///
        /// Cannot be used together with the `--workflow` option.
        #[arg(short, long, value_name = "FLAKE[#ATTR]", conflicts_with = "workflow")]
        flake: Option<String>,

        /// Run all jobs in the workflow.
        ///
        /// Cannot be used together with any `[JOB]` arguments.
        #[arg(long, conflicts_with = "jobs")]
        all_jobs: bool,

        /// Optional dotenv file to read environment variables from.
        #[arg(short, long, value_name = "FILE")]
        env_file: Option<PathBuf>,

        /// Immediately abort on the first job failure.
        #[arg(long)]
        abort: bool,

        /// Timeout for the entire workflow, eg. `1h`.
        #[arg(long, value_name = "DURATION")]
        timeout: Option<humantime::Duration>,

        /// Evaluate but don't run the workflow.
        #[arg(long, conflicts_with_all = ["jobs", "all_jobs"])]
        eval: bool,

        /// In which directory to run the workflow.
        ///
        /// Defaults to the current directory if --workflow is set,
        /// and the directory that `now.nix` is in otherwise
        #[arg(
            short,
            long,
            add = ArgValueCompleter::new(PathCompleter::dir()),
        )]
        cwdir: Option<PathBuf>,

        /// A semicolon-separated list of build machines.
        /// When specified, overrides the remote builders configuration of the host.
        ///
        /// Cannot be used together with the `--local-only` option.
        ///
        /// For more information on the syntax, see:
        /// <https://nix.dev/manual/nix/latest/command-ref/conf-file#conf-builders>
        #[arg(long)]
        builders: Option<String>,

        /// When specified, ignores the remote builders configuration of the host,
        /// running all jobs in the local builder.
        ///
        /// Jobs that cannot run in the local builder will fail.
        ///
        /// Cannot be used together with either the `--builders` or `--remote-only` options.
        #[arg(long, conflicts_with_all = ["builders", "remote_only"])]
        local_only: bool,

        /// When specified, runs all jobs in remote builders,
        /// only using the local runner for job orchestration.
        ///
        /// Cannot be used together with the `--local-only` option.
        #[arg(long)]
        remote_only: bool,

        /// When specified, skips jobs that don't match any builders or runners
        /// and their dependencies, instead of failing.
        #[arg(long)]
        skip: bool,

        /// Whether to use now's binary cache and pinned nixpkgs when building the step runner.
        ///
        /// This avoids having to download and run the compiler toolchain on local and remote builds.
        #[arg(long)]
        use_cache: bool,

        /// Whether to emit traces in Duper instead of colored logs.
        ///
        /// For more information on Duper: <https://duper.dev.br>
        #[arg(long)]
        tracing: bool,
    },
}

fn workflow_filter(path: &Path) -> bool {
    path.is_dir() || path.extension().is_some_and(|extension| extension == "nix")
}

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
            } else {
                cwdir = cwdir_path.parent();
            }
        }
        Err(color_eyre::eyre::eyre!(
            "No workflow found recursively from '{}'",
            canonical_cwdir.to_string_lossy()
        ))
    }
}

fn job_completer() -> Vec<CompletionCandidate> {
    let result: color_eyre::Result<_> = (|| {
        let command_matches = match Command::command().try_get_matches_from(std::env::args_os()) {
            Ok(command_matches) => command_matches,
            Err(_) => Command::command().try_get_matches_from(std::env::args_os().skip(2))?,
        };

        let matches = command_matches
            .subcommand_matches("run")
            .ok_or_eyre("not run subcommand")?;

        let maybe_workflow = matches.try_get_one::<PathBuf>("workflow")?;
        let maybe_flake = matches.try_get_one::<String>("flake")?;
        let workflow = find_workflow(maybe_workflow.cloned(), maybe_flake.cloned())?;

        let jobs_iter = matches.try_get_many::<String>("jobs")?.unwrap_or_default();

        let (sender, ctrl_c) = smol::channel::bounded(1);
        let _ = ctrlc::set_handler(move || {
            let _ = sender.try_send(());
        });

        let environment = smol::block_on(NowEnvironment::get(&workflow, ctrl_c, None, false))?;

        let mut jobs_iter = jobs_iter.rev();
        let current_job = jobs_iter.next();
        let jobs: HashSet<&String> = jobs_iter.collect();

        Ok(environment
            .jobs
            .into_iter()
            .filter_map(|(job, help)| {
                if current_job.is_none_or(|current_job| job.starts_with(current_job))
                    && !jobs.contains(&job)
                {
                    Some(CompletionCandidate::new(job).help(Some(help.into())))
                } else {
                    None
                }
            })
            .collect())
    })();
    result.unwrap_or_default()
}

fn main() -> color_eyre::Result<()> {
    clap_complete::CompleteEnv::with_factory(Command::command).complete();

    match Command::parse() {
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
            )
        }

        Command::Run {
            jobs,
            workflow,
            flake,
            all_jobs,
            env_file,
            abort,
            timeout,
            eval,
            cwdir,
            builders,
            local_only,
            remote_only,
            skip,
            use_cache,
            tracing,
        } => {
            let env_filter = EnvFilter::builder()
                .with_default_directive(LevelFilter::INFO.into())
                .from_env_lossy();
            if tracing {
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

            smol::block_on::<color_eyre::Result<()>>(async {
                let mut environment =
                    NowEnvironment::get(&workflow, ctrl_c.clone(), env_file.as_ref(), use_cache)
                        .await?;
                environment.run_workflow(NowWorkflowParams {
                    workflow,
                    ctrl_c,
                    use_cache,
                    abort,
                    timeout: timeout.map(|timeout| timeout.into()),
                    eval,
                    jobs,
                    all_jobs,
                    builders,
                    local_only,
                    remote_only,
                    skip,
                })
            })?;
        }
    }
    Ok(())
}
