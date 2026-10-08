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
    pin::Pin,
    process::Stdio,
};

use ahash::{HashMap, HashMapExt, HashSet};
use futures::{
    AsyncReadExt, AsyncWriteExt,
    stream::{FuturesOrdered, FuturesUnordered},
};
use petgraph::matrix_graph::NodeIndex;
use serde::Serialize;
use smol::{
    channel::TryRecvError,
    io::{AsyncBufReadExt, BufReader},
    process::{Child, Command},
    stream::StreamExt,
};
use tracing::{info, instrument, warn};

use crate::{
    builder::{
        CurrentDirectoryCheckoutTask,
        local::{BuilderGuard, LocalBuilder, RunnerGuard},
    },
    environment::NowEnvironment,
    workflow::{NowJob, NowStepEnvVar},
};

#[derive(Debug, thiserror::Error)]
pub(crate) enum JobError {
    #[error(
        "No builders match for job '{job_name}' (buildSystem = {build_system}, requiredSystemFeatures = {required_system_features:?})"
    )]
    NoMatchingBuilders {
        job_name: String,
        build_system: String,
        required_system_features: HashSet<String>,
    },
    #[error(
        "No runners match for job '{job_name}' (hostSystem = {host_system}, requiredSystemFeatures = {required_system_features:?})"
    )]
    NoMatchingRunners {
        job_name: String,
        host_system: String,
        required_system_features: HashSet<String>,
    },
    #[error("{0}")]
    Other(color_eyre::Report),
}

impl From<color_eyre::Report> for JobError {
    fn from(value: color_eyre::Report) -> Self {
        JobError::Other(value)
    }
}

pub(crate) type JobResult = (NodeIndex<u32>, Result<(), JobError>);
type JobFut<'a> = Pin<Box<dyn Future<Output = JobResult> + 'a>>;

fn dummy_command() -> color_eyre::Result<Child> {
    let mut command = Command::new("/usr/bin/env");
    command
        .args(["sh", "-c", "echo /dummy"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .env_clear();
    Ok(command.spawn()?)
}

#[derive(Serialize)]
struct ExitCode(Option<i32>);

impl NowEnvironment {
    #[instrument(skip_all, fields(job = job.name, dry_run))]
    async fn run_job(
        &self,
        local_builder: &LocalBuilder,
        job: NowJob,
        dry_run: bool,
    ) -> Result<(), JobError> {
        if !local_builder.has_runner(&job) {
            return Err(JobError::NoMatchingRunners {
                job_name: job.name.clone(),
                host_system: job.host_system.clone(),
                required_system_features: job.required_system_features.clone(),
            });
        }

        if dry_run {
            info!(
                runner = local_builder.hostname,
                is_remote = false,
                "(dry run) Not building derivations for job '{}'...",
                &job.name
            );
        } else {
            info!(
                runner = local_builder.hostname,
                is_remote = false,
                "Building derivations for job '{}'...",
                &job.name
            );
        }

        let (steps, derivations) = {
            let mut steps = Vec::with_capacity(job.steps.len());
            let mut derivations = Vec::new();
            let mut realize_futs: FuturesOrdered<_> = job
                .steps
                .iter()
                .map(|step| async {
                    let step = step.clone();
                    let Some(BuilderGuard {
                        lock: _lock,
                        guard: _guard,
                        receiver,
                        builder,
                    }) = local_builder.get_builder(&job).await?
                    else {
                        return Err(JobError::NoMatchingBuilders {
                            job_name: job.name.clone(),
                            build_system: job.build_system.clone(),
                            required_system_features: job.required_system_features.clone(),
                        });
                    };
                    if matches!(receiver.try_recv(), Ok(()) | Err(TryRecvError::Closed)) {
                        return Err(color_eyre::eyre::eyre!("Runner aborted").into());
                    }

                    let teardown = if let Some(teardown_drv) = step.teardown_drv.as_ref() {
                        let _span = tracing::info_span!(
                            "step-teardown-realize",
                            job = job.name,
                            step = step.name,
                            r#type = "step-teardown-realize",
                        )
                        .entered();
                        if dry_run {
                            Some(PathBuf::from("/dummy"))
                        } else {
                            builder
                                .copy_derivations(
                                    &job.name,
                                    std::slice::from_ref(teardown_drv),
                                    receiver,
                                )
                                .await?;
                            let teardown =
                                builder.realize_derivation(teardown_drv, receiver).await?;
                            builder.fetch_derivation(&teardown, receiver).await?;
                            Some(teardown)
                        }
                    } else {
                        None
                    };
                    let run = {
                        let _span = tracing::info_span!(
                            "step-run-realize",
                            job = job.name,
                            step = step.name,
                            r#type = "step-run-realize",
                        )
                        .entered();
                        if dry_run {
                            PathBuf::from("/dummy")
                        } else {
                            builder
                                .copy_derivations(
                                    &job.name,
                                    std::slice::from_ref(&step.run_drv),
                                    receiver,
                                )
                                .await?;
                            let run = builder.realize_derivation(&step.run_drv, receiver).await?;
                            builder.fetch_derivation(&run, receiver).await?;
                            run
                        }
                    };
                    Ok((step, run, teardown))
                })
                .collect();
            while let Some(result) = realize_futs.next().await {
                let (step, run, teardown) = result?;
                if let Some(teardown) = teardown.clone() {
                    derivations.push(teardown);
                }
                derivations.push(run.clone());
                steps.push((step, run, teardown));
            }
            (steps, derivations)
        };

        let Some(RunnerGuard {
            lock: _guard,
            receiver,
            builder: runner,
        }) = local_builder.get_runner(&job).await?
        else {
            return Err(JobError::NoMatchingRunners {
                job_name: job.name.clone(),
                host_system: job.host_system.clone(),
                required_system_features: job.required_system_features.clone(),
            });
        };
        if matches!(receiver.try_recv(), Ok(()) | Err(TryRecvError::Closed)) {
            return Err(color_eyre::eyre::eyre!("Runner aborted").into());
        }
        let runner_name = runner.get_name();
        let is_remote = runner.is_remote();

        if dry_run {
            info!(
                runner = runner_name,
                is_remote, "(dry run) Not running job '{}'...", &job.name
            );
        } else {
            info!(
                runner = runner_name,
                is_remote, "Running job '{}'...", &job.name
            );
        }

        let mut checkout_child = if dry_run {
            Box::new(CurrentDirectoryCheckoutTask {
                current_directory: PathBuf::from("/dummy"),
            })
        } else {
            runner.checkout(job.checkout)?
        };

        let cwdir = smol::future::or(checkout_child.run(), async {
            let _ = receiver.recv().await;
            Err(color_eyre::eyre::eyre!("Runner aborted"))
        })
        .await?;

        let mut output_vars: HashMap<OsString, OsString> = HashMap::new();

        let mut teardown_stack = Vec::new();

        let steps_fut = async {
            if !dry_run {
                runner
                    .copy_derivations(&job.name, &derivations, receiver)
                    .await?;
            }

            for (step, run, teardown) in steps {
                let _span = tracing::info_span!(
                    "step-run",
                    job = job.name,
                    step = step.name,
                    r#type = "step-run",
                )
                .entered();
                let mut downloads: Vec<PathBuf> = Vec::new();
                {
                    let uploads = self.uploads.lock().expect("not poisoned");
                    for env in step.env.values() {
                        if let NowStepEnvVar::Download(download) = env {
                            if let Some(path) = uploads.get(&download.download_name) {
                                downloads.push(path.clone());
                            } else {
                                return Err(color_eyre::eyre::eyre!(
                                    "No upload named '{}'",
                                    &download.download_name,
                                ));
                            }
                        }
                    }
                }
                if !dry_run && !downloads.is_empty() {
                    runner.download(&downloads, receiver).await?;
                }

                if let Some(teardown) = teardown {
                    teardown_stack.push((step.name.clone(), teardown, step.env.clone()));
                }

                let mut child = if dry_run {
                    dummy_command()?
                } else {
                    runner.run_derivation(&cwdir, run)?
                };
                let mut stdin = child.stdin.take().expect("stdin is piped");
                let mut stdout = child.stdout.take().expect("stdout is piped");
                let stderr = child.stderr.take().expect("stderr is piped");

                let log_task = async {
                    let mut lines = BufReader::new(stderr).lines();
                    while let Some(line) = lines.next().await {
                        if let Ok(line) = line {
                            info!(
                                runner = runner_name,
                                is_remote,
                                step = step.name,
                                "{}",
                                line
                            );
                        } else {
                            break;
                        }
                    }
                };

                let stdin_task = async {
                    let env = self.generate_env_vars_for_step(&step.env, &output_vars)?;
                    for (key, value) in env {
                        stdin.write_all(&key.into_encoded_bytes()).await?;
                        stdin.write_all(b"=").await?;
                        stdin.write_all(&value.into_encoded_bytes()).await?;
                        stdin.write_all(b"\0").await?;
                    }
                    drop(stdin);
                    Ok(())
                };

                let (exit_status, ((), stdin_task)): (_, (_, color_eyre::Result<()>)) =
                    smol::future::zip(child.status(), smol::future::zip(log_task, stdin_task))
                        .await;
                stdin_task?;
                let exit_status = exit_status?;

                if !exit_status.success() {
                    warn!(
                        "$duper.exit_code" =
                            duper::serde::ser::to_string_compact(&ExitCode(exit_status.code()))
                                .expect("valid Duper")
                    );
                    return Err(color_eyre::eyre::eyre!(
                        "Step '{}' failed ({})",
                        &step.name,
                        exit_status
                    ));
                }

                if let Some(output_var) = step.output_var.as_ref() {
                    let mut buf = Vec::new();
                    stdout.read_to_end(&mut buf).await?;
                    info!(
                        runner = runner_name,
                        is_remote,
                        step = step.name,
                        "Set '{}'",
                        output_var,
                    );
                    output_vars.insert(
                        output_var.into(),
                        OsStr::from_bytes(buf.trim_ascii()).into(),
                    );
                } else if let Some(upload_key) = step.upload_key.as_ref() {
                    let mut buf = Vec::new();
                    stdout.read_to_end(&mut buf).await?;
                    let upload_path = PathBuf::from(OsStr::from_bytes(buf.trim_ascii()));
                    if !dry_run {
                        runner.fetch_derivation(&upload_path, receiver).await?;
                    }
                    info!(
                        runner = runner_name,
                        is_remote,
                        step = step.name,
                        "Uploaded '{}' ({})",
                        upload_key,
                        upload_path.to_string_lossy()
                    );
                    self.uploads
                        .lock()
                        .expect("not poisoned")
                        .insert(upload_key.clone(), upload_path);
                }
            }
            Ok(())
        };

        let mut result: Result<(), JobError> = smol::future::or(steps_fut, async {
            if let Some(timeout) = job.timeout {
                smol::Timer::after(timeout).await;
                Err(color_eyre::eyre::eyre!(
                    "Job '{}' timed out after {}",
                    job.name,
                    humantime::Duration::from(timeout)
                ))
            } else {
                smol::future::pending::<color_eyre::Result<()>>().await
            }
        })
        .await
        .map_err(Into::into);

        for (step_name, teardown, step_env) in teardown_stack.into_iter().rev() {
            let _span = tracing::info_span!(
                "step-teardown",
                job = job.name,
                step = step_name,
                r#type = "step-teardown",
            )
            .entered();

            let env_vars = match self.generate_env_vars_for_step(&step_env, &output_vars) {
                Ok(env_vars) => env_vars,
                Err(error) => {
                    warn!(
                        runner = runner_name,
                        is_remote,
                        step = step_name,
                        teardown = true,
                        "Teardown failed ({}); continuing",
                        error
                    );
                    result = result.and_then(|()| {
                        Err(color_eyre::eyre::eyre!(
                            "Teardown for step '{}' failed ({})",
                            step_name,
                            error,
                        )
                        .into())
                    });
                    continue;
                }
            };
            let mut child = if dry_run {
                dummy_command()?
            } else {
                runner.run_derivation(&cwdir, teardown)?
            };
            let mut stdin = child.stdin.take().expect("stdin is piped");
            let stderr = child.stderr.take().expect("stderr is piped");

            let log_task = async {
                let mut lines = BufReader::new(stderr).lines();
                while let Some(line) = lines.next().await {
                    if let Ok(line) = line {
                        info!(
                            runner = runner_name,
                            is_remote,
                            step = step_name,
                            "{}",
                            line
                        );
                    } else {
                        break;
                    }
                }
            };

            let stdin_task = async {
                for (key, value) in env_vars {
                    stdin.write_all(&key.into_encoded_bytes()).await?;
                    stdin.write_all(b"=").await?;
                    stdin.write_all(&value.into_encoded_bytes()).await?;
                    stdin.write_all(b"\0").await?;
                }
                drop(stdin);
                Ok(())
            };

            let (exit_status, ((), stdin_task)): (_, (_, color_eyre::Result<()>)) =
                smol::future::zip(child.status(), smol::future::zip(log_task, stdin_task)).await;

            if let Err(error) = stdin_task {
                warn!(
                    runner = runner_name,
                    is_remote,
                    step = step_name,
                    teardown = true,
                    "Teardown task failed ({}); continuing",
                    error
                );
                result = result.and_then(|()| {
                    Err(color_eyre::eyre::eyre!(
                        "Teardown task for step '{}' failed ({})",
                        step_name,
                        error,
                    )
                    .into())
                });
                continue;
            }

            let exit_status = match exit_status {
                Ok(exit_status) => exit_status,
                Err(error) => {
                    warn!(
                        runner = runner_name,
                        is_remote,
                        step = step_name,
                        teardown = true,
                        "Teardown failed ({}); continuing",
                        error
                    );
                    result = result.and_then(|()| {
                        Err(color_eyre::eyre::eyre!(
                            "Teardown for step '{}' failed ({})",
                            step_name,
                            error,
                        )
                        .into())
                    });
                    continue;
                }
            };
            if !exit_status.success() {
                warn!(
                    "$duper.exit_code" =
                        duper::serde::ser::to_string_compact(&ExitCode(exit_status.code()))
                            .expect("valid Duper"),
                    runner = runner_name,
                    is_remote,
                    step = step_name,
                    teardown = true,
                    "Teardown failed ({}); continuing",
                    exit_status
                );
                result = result.and_then(|()| {
                    Err(color_eyre::eyre::eyre!(
                        "Teardown for step '{}' failed ({})",
                        step_name,
                        exit_status
                    )
                    .into())
                });
            }
        }

        let result = result.and(if dry_run {
            Ok(())
        } else {
            runner
                .undo_checkout(job.checkout, &cwdir)
                .await
                .map_err(Into::into)
        });

        if result.is_ok() {
            info!("success" = true);
        } else {
            info!("success" = false);
        }

        result
    }

    pub(crate) fn run_job_single<'a>(
        &'a self,
        local_builder: &'a LocalBuilder,
        job: NowJob,
        node_index: NodeIndex<u32>,
        dry_run: bool,
    ) -> JobFut<'a> {
        Box::pin(async move {
            let result = self.run_job(local_builder, job, dry_run).await;
            (node_index, result)
        })
    }

    pub(crate) fn run_jobs_multiple<'a>(
        &'a self,
        local_builder: &'a LocalBuilder,
        jobs: Vec<NowJob>,
        node_index: NodeIndex<u32>,
        dry_run: bool,
    ) -> JobFut<'a> {
        let mut fail_fast = FuturesUnordered::new();
        let mut no_fail_fast = FuturesUnordered::new();

        for job in jobs {
            if job
                .strategy
                .as_ref()
                .is_none_or(|strategy| strategy.fail_fast)
            {
                fail_fast.push(self.run_job(local_builder, job, dry_run));
            } else {
                no_fail_fast.push(self.run_job(local_builder, job, dry_run));
            }
        }

        Box::pin(async move {
            let (fail_fast, no_fail_fast) = smol::future::zip(
                async move {
                    while let Some(future) = fail_fast.next().await {
                        future?;
                    }
                    Ok(())
                },
                async move {
                    let mut result = Ok(());
                    while let Some(future) = no_fail_fast.next().await {
                        result = result.and(future);
                    }
                    result
                },
            )
            .await;
            (node_index, fail_fast.and(no_fail_fast))
        })
    }
}
