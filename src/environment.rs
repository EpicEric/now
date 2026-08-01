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
    collections::{BTreeMap, BTreeSet, HashMap, HashSet},
    ffi::OsString,
    io::Write,
    os::unix::ffi::OsStringExt,
    path::{Path, PathBuf},
    process::Command,
    sync::{LazyLock, Mutex},
};

use tracing::instrument;

use crate::{
    project::{ProjectSource, create_nix_project_source},
    secret::SecretString,
    utils::get_random_string,
    workflow::{NowJob, NowJobContainer, NowStepEnvVar, NowWorkflow},
};

pub(crate) static EVAL_ID: LazyLock<String> = LazyLock::new(|| get_random_string(10));

pub(crate) struct NowEnvironment {
    pub(crate) nix_project_source: ProjectSource,
    pub(crate) secrets: HashMap<String, SecretString>,
    pub(crate) vars: HashMap<String, String>,
    pub(crate) jobs: BTreeMap<String, String>,
    pub(crate) local_env: HashMap<OsString, OsString>,
    pub(crate) uploads: Mutex<HashMap<String, PathBuf>>,
}

struct ParsedWorkflow {
    vars: HashSet<OsString>,
    secrets: HashSet<OsString>,
    jobs: BTreeMap<String, String>,
}

impl NowEnvironment {
    #[instrument]
    pub(crate) fn get(
        workflow: &Path,
        env_file: Option<&PathBuf>,
        nixpkgs_expr: &str,
        use_cache: bool,
    ) -> color_eyre::Result<NowEnvironment> {
        let mut env_vars: HashMap<OsString, OsString> = HashMap::new();
        if let Some(env_file) = env_file {
            env_vars.extend(
                dotenvy::from_path_iter(env_file)?.filter_map(|result| {
                    result.ok().map(|(key, value)| (key.into(), value.into()))
                }),
            );
        };
        env_vars.extend(std::env::vars_os());

        let nix_project_source = create_nix_project_source()?;

        let parsed_workflow = Self::parse_workflow(
            workflow,
            nix_project_source.as_ref(),
            nixpkgs_expr,
            use_cache,
        )?;

        let secrets: color_eyre::Result<HashMap<String, SecretString>> = parsed_workflow
            .secrets
            .into_iter()
            .filter_map(|secret| {
                let Some(value) = env_vars.remove(&secret) else {
                    return None;
                };
                let key = match secret.into_string() {
                    Ok(secret) => secret,
                    Err(os_string) => {
                        return Some(Err(color_eyre::eyre::eyre!(
                            "Invalid value for {} envvar",
                            String::from_utf8_lossy(os_string.as_encoded_bytes())
                        )));
                    }
                };
                let value = match value.into_string() {
                    Ok(value) => SecretString::new(value),
                    Err(os_string) => {
                        return Some(Err(color_eyre::eyre::eyre!(
                            "Invalid value for {} envvar",
                            String::from_utf8_lossy(os_string.as_encoded_bytes())
                        )));
                    }
                };
                Some(Ok((key, value)))
            })
            .collect();
        let secrets = secrets?;

        let vars: color_eyre::Result<HashMap<String, String>> = parsed_workflow
            .vars
            .into_iter()
            .filter_map(|var| {
                let Some(value) = env_vars.remove(&var) else {
                    return None;
                };
                let key = match var.into_string() {
                    Ok(var) => var,
                    Err(os_string) => {
                        return Some(Err(color_eyre::eyre::eyre!(
                            "Invalid value for {} envvar",
                            String::from_utf8_lossy(os_string.as_encoded_bytes())
                        )));
                    }
                };
                let value = match value.into_string() {
                    Ok(value) => value,
                    Err(os_string) => {
                        return Some(Err(color_eyre::eyre::eyre!(
                            "Invalid value for {} envvar",
                            String::from_utf8_lossy(os_string.as_encoded_bytes())
                        )));
                    }
                };
                Some(Ok((key, value)))
            })
            .collect();
        let vars = vars?;

        Ok(Self {
            nix_project_source,
            secrets,
            vars,
            jobs: parsed_workflow.jobs,
            local_env: env_vars,
            uploads: Default::default(),
        })
    }

    #[instrument]
    fn parse_workflow(
        workflow: &Path,
        nix_project_source: &Path,
        nixpkgs_expr: &str,
        use_cache: bool,
    ) -> color_eyre::Result<ParsedWorkflow> {
        let workflow_canonical = std::fs::canonicalize(workflow)?;
        let workflow_str = workflow_canonical
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
        let workflow_path = format!("(/. + {})", serde_json::to_string(&workflow_str)?);

        let nix_env = nix_project_source.join("nix/env.nix");
        let nix_env_canonical = std::fs::canonicalize(&nix_env)?;
        let nix_env_str = nix_env_canonical
            .to_str()
            .ok_or_else(|| color_eyre::eyre::eyre!("non-UTF8 path"))?;
        let nix_env_path = format!("(/. + {})", serde_json::to_string(&nix_env_str)?);

        let workflow_args = format!("{{ nixpkgs = ({}); }}", nixpkgs_expr);

        let eval_id = serde_json::to_string(&*EVAL_ID)?;
        let nix_project_path = serde_json::to_string(nix_project_source)?;

        let nix_command = format!(
            "import {nix_env_path} {workflow_args} {{ workflow = {workflow_path}; evalId = {eval_id}; useCache = {use_cache}; gcrootDir = {nix_project_path}; }}"
        );

        let mut command = Command::new("nix");
        command.args([
            "--extra-experimental-features",
            "nix-command",
            "eval",
            "--impure",
            "--json",
        ]);
        let output = command.arg("--expr").arg(nix_command).output()?;

        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!(
                "Failed to parse workflow for variables"
            ));
        }

        let workflow: NowWorkflow = serde_json::from_slice(&output.stdout)?;

        let mut secrets: HashSet<OsString> = HashSet::new();

        let vars_regex = regex::bytes::Regex::new(&format!("@@__nowVar_{}_([^@]+)@@", *EVAL_ID))
            .expect("valid regex");
        let vars: HashSet<OsString> = vars_regex
            .captures_iter(&output.stdout)
            .map(|needle| OsString::from_vec(needle.get(1).expect("is match").as_bytes().to_vec()))
            .collect();

        let mut job_fn = |job: &NowJob| {
            for step in &job.steps {
                for env_value in step.env.values() {
                    if let NowStepEnvVar::Secret(secret) = env_value {
                        secrets.insert(OsString::from_vec(secret.secret_name.as_bytes().to_vec()));
                    }
                }
            }
        };

        for job in workflow.jobs.values() {
            match job {
                NowJobContainer::Single(job) => (job_fn)(job),
                NowJobContainer::Multiple(job_vec) => {
                    for job in job_vec {
                        (job_fn)(job)
                    }
                }
            }
        }

        let mut intersection = secrets.intersection(&vars);
        if let Some(secret) = intersection.next() {
            let intersection_count = intersection.count();
            if intersection_count == 0 {
                return Err(color_eyre::eyre::eyre!(
                    "Invalid workflow: secret '{}' cannot also be used as a regular variable",
                    String::from_utf8_lossy(secret.as_encoded_bytes())
                ));
            } else {
                return Err(color_eyre::eyre::eyre!(
                    "Invalid workflow: secret '{}' and {intersection_count} other(s) cannot also be used as regular variables",
                    String::from_utf8_lossy(secret.as_encoded_bytes())
                ));
            }
        }

        let jobs = workflow
            .jobs
            .iter()
            .map(|(key, value)| {
                let value: String = match value {
                    NowJobContainer::Single(job) => job.name.clone(),
                    NowJobContainer::Multiple(job_vec) => {
                        let job_names: BTreeSet<String> =
                            job_vec.iter().map(|job| job.name.clone()).collect();
                        let mut joined_name = String::new();
                        for name in job_names {
                            if !joined_name.is_empty() {
                                joined_name.push_str(", ");
                            }
                            joined_name.push_str(&name);
                        }
                        joined_name
                    }
                };
                (key.clone(), value)
            })
            .collect();

        Ok(ParsedWorkflow {
            vars,
            secrets,
            jobs,
        })
    }

    pub(crate) fn generate_env_vars_for_step(
        &self,
        step_env: &HashMap<String, NowStepEnvVar>,
    ) -> color_eyre::Result<HashMap<OsString, OsString>> {
        let mut map: HashMap<OsString, OsString> = HashMap::with_capacity(step_env.len() + 1);

        {
            let uploads = self.uploads.lock().expect("not poisoned");
            for (key, value) in step_env {
                match value {
                    NowStepEnvVar::Plain(value) => {
                        map.insert(key.into(), value.into());
                    }
                    NowStepEnvVar::Secret(secret) => {
                        map.insert(
                            key.into(),
                            self.secrets
                                .get(&secret.secret_name)
                                .ok_or_else(|| {
                                    color_eyre::eyre::eyre!(
                                        "Missing secret '{}'",
                                        &secret.secret_name
                                    )
                                })?
                                .get_secret_value()
                                .into(),
                        );
                    }
                    NowStepEnvVar::Download(download) => {
                        let download_path =
                            uploads.get(&download.download_name).ok_or_else(|| {
                                color_eyre::eyre::eyre!(
                                    "Missing download '{}'",
                                    &download.download_name
                                )
                            })?;
                        map.insert(key.into(), download_path.into());
                    }
                }
            }
        }

        match supports_color::on_cached(supports_color::Stream::Stderr) {
            Some(_) => {
                map.insert("FORCE_COLOR".into(), "1".into());
            }
            None => {
                map.insert("NO_COLOR".into(), "1".into());
            }
        }

        Ok(map)
    }
}
