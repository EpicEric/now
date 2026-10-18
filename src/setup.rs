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
    ffi::{OsStr, OsString},
    os::unix::ffi::OsStrExt,
    path::PathBuf,
};

use clap::{CommandFactory, Parser};
use color_eyre::eyre::eyre;

use crate::{command::Command, eyre::install_tracing_hook, utils::parse_bool_from_bytes};

fn force_ansi_colors_on_ci_runners(env_vars: &ahash::HashMap<OsString, OsString>) {
    for key in [
        OsStr::from_bytes(b"FORGEJO_ACTIONS"),
        OsStr::from_bytes(b"GITEA_ACTIONS"),
        OsStr::from_bytes(b"GITHUB_ACTIONS"),
        OsStr::from_bytes(b"GITLAB_CI"),
    ] {
        if env_vars
            .get(key)
            .is_some_and(|value| parse_bool_from_bytes(value.as_encoded_bytes()))
        {
            // Safety: called before any threads are spawned.
            unsafe { std::env::set_var("FORCE_COLOR", "1") };
            return;
        }
    }

    if env_vars
        .get(OsStr::from_bytes(b"CI"))
        .is_some_and(|value| parse_bool_from_bytes(value.as_encoded_bytes()))
    {
        if env_vars
            .get(OsStr::from_bytes(b"TANGLED_PIPELINE_ID"))
            .is_some_and(|value| !value.is_empty())
        {
            // Safety: called before any threads are spawned.
            unsafe { std::env::set_var("FORCE_COLOR", "1") };
            return;
        }
    }
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
struct Args {
    #[arg(hide = true)]
    workflow: Option<PathBuf>,
    #[command(subcommand)]
    command: Command,
}

pub(crate) fn setup() -> color_eyre::Result<Command> {
    clap_complete::CompleteEnv::with_factory(Args::command).complete();
    let args = Args::parse();
    let command = match args.command {
        Command::Init { workflow } => {
            if args.workflow.is_some() && workflow.is_some() {
                return Err(eyre!("Conflicting workflow options"));
            }
            Command::Init {
                workflow: args.workflow.or(workflow),
            }
        }
        Command::List {
            workflow,
            flake,
            env_file,
            cwdir,
            tree,
        } => {
            if args.workflow.is_some() && (workflow.is_some() || flake.is_some()) {
                return Err(eyre!("Conflicting workflow options"));
            }
            Command::List {
                workflow: args.workflow.or(workflow),
                flake,
                env_file,
                cwdir,
                tree,
            }
        }
        Command::Eval {
            workflow,
            flake,
            env_file,
            cwdir,
        } => {
            if args.workflow.is_some() && (workflow.is_some() || flake.is_some()) {
                return Err(eyre!("Conflicting workflow options"));
            }
            Command::Eval {
                workflow: args.workflow.or(workflow),
                flake,
                env_file,
                cwdir,
            }
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
            termination_timeout,
            timeout,
            keep_alive,
            cwdir,
            builders,
            cores,
            local_only,
            remote_only,
            skip,
            logging,
            tracing,
        } => {
            if args.workflow.is_some() && (workflow.is_some() || flake.is_some()) {
                return Err(eyre!("Conflicting workflow options"));
            }
            if tracing.is_some() {
                install_tracing_hook()?;
            } else {
                color_eyre::install()?;
            }
            Command::Run {
                jobs,
                workflow: args.workflow.or(workflow),
                flake,
                dry_run,
                all_jobs,
                env_file,
                gcroot_dir,
                abort,
                termination_timeout,
                timeout,
                keep_alive,
                cwdir,
                builders,
                cores,
                local_only,
                remote_only,
                skip,
                logging,
                tracing,
            }
        }
    };

    let env_vars: ahash::HashMap<_, _> = std::env::vars_os().collect();
    force_ansi_colors_on_ci_runners(&env_vars);

    Ok(command)
}
