// cix: A Nix-based CI helper
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

use std::{collections::HashMap, io::Write, path::PathBuf, process::Command};

use serde::Deserialize;

use crate::{environment::CixEnvironment, project::create_project_source};

#[derive(Debug, Deserialize)]
pub(crate) struct CixWorkflow {
    pub(crate) name: Option<String>,
    pub(crate) jobs: HashMap<String, CixJobContainer>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(crate) enum CixJobContainer {
    Single(CixJob),
    Multiple(Vec<CixJob>),
}

#[derive(Debug, Deserialize)]
pub(crate) struct CixJob {
    pub(crate) name: Option<String>,
    #[serde(rename = "buildSystem")]
    pub(crate) build_system: String,
    #[serde(rename = "hostSystem")]
    pub(crate) host_system: String,
    #[serde(rename = "system-features")]
    pub(crate) system_features: Vec<String>,
    pub(crate) strategy: Option<CixStrategy>,
    pub(crate) needs: Option<Vec<String>>,
    pub(crate) steps: Vec<CixStep>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CixStrategy {
    #[serde(rename = "fail-fast")]
    pub(crate) fail_fast: bool,
}

#[derive(Debug, Deserialize)]
pub(crate) struct CixStep {
    pub(crate) run: PathBuf,
    pub(crate) teardown: Option<PathBuf>,
    pub(crate) env: HashMap<String, CixStepEnvVar>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
pub(crate) enum CixStepEnvVar {
    Plain(String),
    Secret(CixStepSecret),
}

#[derive(Debug, Deserialize)]
pub(crate) struct CixStepSecret {
    #[serde(rename = "__cixSecret")]
    pub(crate) secret_name: String,
}

impl CixEnvironment {
    pub(crate) fn run_workflow(
        &mut self,
        workflow: PathBuf,
        dry_run: bool,
        show_trace: bool,
    ) -> color_eyre::Result<()> {
        let workflow_canonical = std::fs::canonicalize(&workflow)?;
        let workflow_str = workflow_canonical
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
        let workflow_path = format!("(/. + {})", serde_json::to_string(&workflow_str)?);

        let mut nix_workflow = create_project_source()?;
        nix_workflow.push("nix");
        nix_workflow.push("workflow.nix");
        let nix_workflow_canonical = std::fs::canonicalize(&nix_workflow)?;
        let nix_workflow_str = nix_workflow_canonical
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
        let nix_workflow_path = format!("(/. + {})", serde_json::to_string(&nix_workflow_str)?);

        let secrets_json = serde_json::to_string(&serde_json::to_string(
            &self.secrets.keys().collect::<Vec<_>>(),
        )?)?;
        let vars_json = serde_json::to_string(&serde_json::to_string(&self.vars)?)?;

        let nix_command = format!(
            "(import {nix_workflow_path} {{ }}) {workflow_path} {{ secrets = builtins.fromJSON {secrets_json}; vars = builtins.fromJSON {vars_json}; }}"
        );

        let mut command = Command::new("nix-instantiate");
        command.args(["--impure", "--eval", "--strict", "--raw"]);
        if show_trace {
            command.arg("--show-trace");
        }
        let output = command.arg("--expr").arg(nix_command).output()?;

        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!("Failed to evaluate cix workflow"));
        }

        let workflow: CixWorkflow = serde_json::from_slice(&output.stdout)?;

        if dry_run {
            println!("{:?}", &workflow);
            return Ok(());
        }

        Ok(())
    }
}
