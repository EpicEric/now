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
    num::NonZeroUsize,
    path::{Path, PathBuf},
};

use ahash::HashSet;
use clap::{CommandFactory, Parser, ValueEnum};
use clap_complete::{ArgValueCandidates, ArgValueCompleter, CompletionCandidate, PathCompleter};
use color_eyre::eyre::OptionExt;

use crate::{environment::NowEnvironment, find_workflow};

#[derive(Debug, Clone, Copy, Default, ValueEnum)]
pub(crate) enum TracingMode {
    /// (default) Don't include ANSI colors in output.
    #[default]
    NoColors,
    /// Include ANSI colors in output.
    Colors,
}

static LONG_ABOUT: &str = "now - Nix-based distributed command runner.

\x1b[1;4mExamples:\x1b[0m
  \x1b[2m# Initialize a basic workflow in ./now.nix\x1b[0m
  now init

  \x1b[2m# Load envvars from a dotenv file and run the default job(s)\x1b[0m
  now run --env-file .env

  \x1b[2m# Run the \"deploy\" job (and all dependencies) from the specified workflow,\x1b[0m
  \x1b[2m# and specify a remote builder for the run\x1b[0m
  now run deploy \\
    --builders \"ssh://mac aarch64-darwin\" \\
    --workflow .now/remote.nix

  \x1b[2m# Abort immediately on the first failing job,\x1b[0m
  \x1b[2m# and run all jobs on the local machine\x1b[0m
  now run --abort --local-only";

#[derive(Parser)]
#[command(name = "now", version, about, long_about = LONG_ABOUT)]
pub(crate) enum Command {
    /// Initialize a basic workflow.
    Init {
        /// Path to the workflow.
        workflow: Option<PathBuf>,
    },

    /// List the jobs available in the workflow.
    List {
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

        /// Optional dotenv file to read environment variables from.
        #[arg(short, long, value_name = "FILE")]
        env_file: Option<PathBuf>,

        /// In which directory to evaluate the workflow.
        #[arg(
            short,
            long,
            add = ArgValueCompleter::new(PathCompleter::dir()),
        )]
        cwdir: Option<PathBuf>,

        /// Whether to print jobs as a graphviz-compatible .dot tree graph.
        #[arg(short, long)]
        tree: bool,
    },

    /// Evaluate a workflow, printing its JSON representation.
    Eval {
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

        /// Optional dotenv file to read environment variables from.
        #[arg(short, long, value_name = "FILE")]
        env_file: Option<PathBuf>,

        /// In which directory to evaluate the workflow.
        #[arg(
            short,
            long,
            add = ArgValueCompleter::new(PathCompleter::dir()),
        )]
        cwdir: Option<PathBuf>,
    },

    /// Run one or more jobs.
    Run {
        /// Jobs to target in this run. Unix-style globs are supported.
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

        /// Don't realize derivations or run jobs.
        ///
        /// Useful for debugging workflows before running them.
        #[arg(long)]
        dry_run: bool,

        /// Run all jobs in the workflow.
        ///
        /// Cannot be used together with any `[JOB]` arguments.
        #[arg(long, conflicts_with = "jobs")]
        all_jobs: bool,

        /// Optional dotenv file to read environment variables from.
        #[arg(short, long, value_name = "FILE")]
        env_file: Option<PathBuf>,

        /// Directory where Nix GC roots for realized steps are kept.
        ///
        /// Defaults to a temporary directory removed when `now` exits.
        #[arg(
            long,
            value_name = "DIR",
            add = ArgValueCompleter::new(PathCompleter::dir()),
        )]
        gcroot_dir: Option<PathBuf>,

        /// Immediately abort on the first job failure.
        #[arg(long)]
        abort: bool,

        /// Timeout for the entire workflow, eg. `1h`.
        #[arg(long, value_name = "DURATION")]
        timeout: Option<humantime::Duration>,

        /// How often to send keep-alive messages to remote hosts.
        /// After not receiving a response 3 times, the job fails.
        ///
        /// Only set if the duration is greater than or equal to `1s`.
        ///
        /// Cannot be used together with the `--local-only` option.
        #[arg(long)]
        keep_alive: Option<humantime::Duration>,

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

        /// How many simultaneous jobs to use for local builds.
        ///
        /// Defaults to the number of physical cores in the current machine.
        ///
        /// Cannot be used together with the `--remote-only` option.
        #[arg(long, conflicts_with = "remote_only")]
        cores: Option<NonZeroUsize>,

        /// When specified, ignores the remote builders configuration of the host,
        /// running all jobs in the local builder.
        ///
        /// Jobs that cannot run in the local builder will fail.
        ///
        /// Cannot be used together with either the `--builders`, `--remote-only`,
        /// or `--keep-alive` options.
        #[arg(long, conflicts_with_all = ["builders", "remote_only", "keep_alive"])]
        local_only: bool,

        /// When specified, runs all jobs in remote builders,
        /// only using the local runner for job orchestration.
        ///
        /// Cannot be used together with either the `--cores` or `--local-only` options.
        #[arg(long)]
        remote_only: bool,

        /// When specified, skips jobs that don't match any builders or runners
        /// and their dependencies, instead of failing.
        #[arg(long)]
        skip: bool,

        /// Whether to emit traces in Duper instead of colored logs.
        ///
        /// You can also set whether ANSI colors are included in the traces or not.
        ///
        /// For more information on Duper: <https://duper.dev.br>
        #[arg(
            long,
            value_enum,
            num_args = 0..=1,
            default_missing_value = "no-colors",
        )]
        tracing: Option<TracingMode>,
    },
}

fn workflow_filter(path: &Path) -> bool {
    path.is_dir() || path.extension().is_some_and(|extension| extension == "nix")
}

fn job_completer() -> Vec<CompletionCandidate> {
    let result: color_eyre::Result<_> = (|| {
        let command_matches = match Command::command().try_get_matches_from(std::env::args_os()) {
            Ok(command_matches) => command_matches,
            Err(_) => Command::command().try_get_matches_from(std::env::args_os().skip(2))?,
        };

        let matches = command_matches
            .subcommand_matches("run")
            .ok_or_eyre("Not run subcommand")?;

        let maybe_workflow = matches.try_get_one::<PathBuf>("workflow")?;
        let maybe_flake = matches.try_get_one::<String>("flake")?;
        let workflow = find_workflow(maybe_workflow.cloned(), maybe_flake.cloned())?;

        let jobs_iter = matches.try_get_many::<String>("jobs")?.unwrap_or_default();

        let (sender, ctrl_c) = smol::channel::bounded(1);
        let _ = ctrlc::set_handler(move || {
            let _ = sender.try_send(());
        });

        let environment = smol::block_on(
            NowEnvironment::builder()
                .workflow(&workflow)
                .ctrl_c(ctrl_c)
                .build(),
        )?;

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
