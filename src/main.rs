// now: A Nix-based distributed command runner
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
    str::FromStr,
    time::Duration,
};

use clap::{CommandFactory, Parser, ValueEnum};
use clap_complete::{ArgValueCandidates, ArgValueCompleter, CompletionCandidate, PathCompleter};
use color_eyre::eyre::Context;
use tracing::level_filters::LevelFilter;
use tracing_duper::DuperLayer;
use tracing_subscriber::{EnvFilter, Layer, layer::SubscriberExt, util::SubscriberInitExt};

use crate::{
    environment::NowEnvironment, subscriber::NowSubscriberLayer, workflow::NowWorkflowParams,
};

mod builder;
mod deserialize;
mod environment;
mod job;
mod project;
mod secret;
mod subscriber;
mod utils;
mod workflow;

#[doc(hidden)]
#[derive(Debug, Copy, Clone, PartialEq, Eq, PartialOrd, Ord, ValueEnum)]
pub(crate) enum CheckoutStrategy {
    /// Don't checkout; create a fresh directory for every job.
    None,
    /// Run commands at the local directory.
    /// On remote builders, copy non-ignored files from the local directory.
    Default,
}

static LONG_ABOUT: &str = "now - Nix-based distributed command runner.

\x1b[1;4mExamples:\x1b[0m
  \x1b[2m# Initialize a basic workflow in ./now.nix\x1b[0m
  now init

  \x1b[2m# Load envvars from a dotenv file\x1b[0m
  now run --env-file .env .now/workflow-with-secrets.nix

  \x1b[2m# Run the \"deploy\" job (and all dependencies),
  # and specify a remote builder for the run\x1b[0m
  now run \\
    --job deploy \\
    --builders \"ssh://mac aarch64-darwin\" \\
    .now/remote.nix

  \x1b[2m# Abort immediately on first failing job,
  # and don't checkout the current directory\x1b[0m
  now run \\
    --abort \\
    --checkout none \\
    .now/fresh-dir.nix";

#[derive(Parser)]
#[command(name = "now", version, about, long_about = LONG_ABOUT)]
enum Command {
    /// Initialize a basic workflow.
    Init {
        /// Path to the workflow.
        workflow: Option<PathBuf>,
    },

    /// Run a workflow.
    Run {
        /// Path to the workflow.
        #[arg(add = ArgValueCompleter::new(PathCompleter::any().filter(workflow_filter)))]
        workflow: PathBuf,

        /// Jobs to target in this run.
        ///
        /// If unspecified, the default jobs of the workflow are run.
        /// If there are no default jobs in the workflow, all jobs are run.
        ///
        /// Cannot be used together with the `--all-jobs` option.
        #[arg(
            short,
            long = "job",
            value_name = "JOB",
            add = ArgValueCandidates::new(job_completer)
        )]
        jobs: Option<Vec<String>>,

        /// If set, all jobs are run.
        ///
        /// Cannot be used together with the `--job` option.
        #[arg(long)]
        all_jobs: bool,

        /// Optional dotenv file to read environment variables from.
        #[arg(short, long, value_name = "FILE")]
        env_file: Option<PathBuf>,

        /// Immediately abort on job failure.
        #[arg(long)]
        abort: bool,

        /// Timeout for the entire workflow, eg. `1h`.
        #[arg(long, value_parser = validate_duration, value_name = "DURATION")]
        timeout: Option<Duration>,

        /// Evaluate but don't run the workflow.
        #[arg(long)]
        eval: bool,

        /// Strategy for checking out the current working directory.
        #[arg(
            long = "checkout",
            value_enum,
            default_value_t = CheckoutStrategy::Default,
            value_name = "STRATEGY",
        )]
        checkout_strategy: CheckoutStrategy,

        /// A semicolon-separated list of build machines.
        ///
        /// When specified, overrides the remote builders configuration of the host.
        ///
        /// For more information on the syntax, see:
        /// <https://nix.dev/manual/nix/latest/command-ref/conf-file#conf-builders>
        #[arg(short, long)]
        builders: Option<String>,

        /// Nix expression that evaluates to nixpkgs.
        #[arg(
            short,
            long = "nixpkgs",
            default_value = "<nixpkgs>",
            value_name = "EXPRESSION"
        )]
        nixpkgs_expr: String,

        /// Whether to use now's binary cache and pinned nixpkgs when building the step runner.
        ///
        /// This avoids having to download and run the compiler toolchain on local and remote builds.
        #[arg(long)]
        use_cache: bool,

        /// Whether to emit traces in Duper instead of colored logs.
        ///
        /// For more information on Duper: <https://duper.dev.br/>
        #[arg(long)]
        tracing: bool,
    },
}

fn validate_duration(value: &str) -> color_eyre::Result<Duration> {
    Ok(humantime::Duration::from_str(value)
        .with_context(|| "invalid duration")?
        .into())
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
            mut workflow,
            jobs,
            all_jobs,
            env_file,
            abort,
            timeout,
            eval,
            checkout_strategy,
            builders,
            nixpkgs_expr,
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

            if all_jobs && jobs.is_some() {
                return Err(color_eyre::eyre::eyre!(
                    "Conflicting --all-jobs and --job options"
                ));
            }
            if all_jobs && eval {
                return Err(color_eyre::eyre::eyre!(
                    "Conflicting --abort and --all-jobs options"
                ));
            }
            if eval && jobs.is_some() {
                return Err(color_eyre::eyre::eyre!(
                    "Conflicting --eval and --job options"
                ));
            }
            if abort && eval {
                return Err(color_eyre::eyre::eyre!(
                    "Conflicting --abort and --eval options"
                ));
            }

            if workflow.is_dir() {
                let now = workflow.join("now.nix");
                if now.exists() && !now.is_dir() {
                    workflow = now;
                } else {
                    return Err(color_eyre::eyre::eyre!(
                        "Workflow 'now.nix' not found in directory '{}'",
                        workflow.to_string_lossy()
                    ));
                }
            } else if !workflow.exists() {
                return Err(color_eyre::eyre::eyre!(
                    "Workflow '{}' not found",
                    workflow.to_string_lossy()
                ));
            }

            let mut environment =
                NowEnvironment::get(&workflow, env_file.as_ref(), &nixpkgs_expr, use_cache)?;
            environment.run_workflow(NowWorkflowParams {
                workflow,
                nixpkgs_expr,
                use_cache,
                abort,
                timeout,
                eval,
                jobs,
                all_jobs,
                checkout_strategy,
                builders,
            })?;
        }
    }
    Ok(())
}

fn workflow_filter(path: &Path) -> bool {
    path.is_dir() || path.extension().is_some_and(|extension| extension == "nix")
}

fn job_completer() -> Vec<CompletionCandidate> {
    let Ok(command_matches) = Command::command().try_get_matches_from(std::env::args_os().skip(2))
    else {
        return vec![];
    };
    let Some(matches) = command_matches.subcommand_matches("run") else {
        return vec![];
    };

    let Ok(Some(workflow)) = matches.try_get_one::<PathBuf>("workflow") else {
        return vec![];
    };
    let Ok(Some(jobs_iter)) = matches.try_get_many::<String>("jobs") else {
        return vec![];
    };

    let Ok(environment) = NowEnvironment::get(workflow, None, "<nixpkgs>", false) else {
        return vec![];
    };

    let mut jobs_iter = jobs_iter.rev();
    let current_job = jobs_iter.next();
    let jobs: HashSet<&String> = jobs_iter.collect();

    environment
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
        .collect()
}
