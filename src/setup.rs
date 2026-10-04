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
};

use clap::{CommandFactory, Parser};

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

pub(crate) fn setup() -> color_eyre::Result<Command> {
    clap_complete::CompleteEnv::with_factory(Command::command).complete();
    let command = Command::parse();
    if let Command::Run { tracing, .. } = &command
        && tracing.is_some()
    {
        install_tracing_hook()?;
    } else {
        color_eyre::install()?;
    }

    let env_vars: ahash::HashMap<_, _> = std::env::vars_os().collect();
    force_ansi_colors_on_ci_runners(&env_vars);

    Ok(command)
}
