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

use std::{collections::HashSet, ffi::OsStr, os::unix::ffi::OsStrExt, path::PathBuf, pin::Pin};

use futures::{
    AsyncReadExt,
    stream::{FuturesOrdered, FuturesUnordered},
};
use petgraph::matrix_graph::NodeIndex;
use smol::{
    channel::TryRecvError,
    io::{AsyncBufReadExt, BufReader},
    stream::StreamExt,
};
use tracing::{info, instrument, warn};

use crate::{
    builder::local::{BuilderGuard, LocalBuilder, RunnerGuard},
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

impl NowEnvironment {
    #[instrument(skip_all, fields(job = job.name))]
    async fn run_job(&self, local_builder: &LocalBuilder, job: NowJob) -> Result<(), JobError> {
        info!(
            runner = local_builder.hostname,
            is_remote = false,
            "Building derivations for job '{}'...",
            &job.name
        );

        let (steps, derivations) = {
            let mut steps = Vec::with_capacity(job.steps.len());
            let mut derivations = Vec::new();
            let mut realize_futs: FuturesOrdered<_> = job
                .steps
                .iter()
                .cloned()
                .map(|step| async {
                    let (_lock, _guard, receiver, builder) =
                        match local_builder.get_builder(&job).await? {
                            Some(BuilderGuard {
                                lock,
                                guard,
                                receiver,
                                builder,
                            }) => (lock, guard, receiver, builder),
                            None => {
                                return Err(JobError::NoMatchingBuilders {
                                    job_name: job.name.clone(),
                                    build_system: job.build_system.clone(),
                                    required_system_features: job.required_system_features.clone(),
                                });
                            }
                        };
                    if matches!(receiver.try_recv(), Ok(()) | Err(TryRecvError::Closed)) {
                        return Err(color_eyre::eyre::eyre!("Runner aborted").into());
                    }

                    let teardown = if let Some(teardown_drv) = step.teardown_drv.as_ref() {
                        let _span = tracing::debug_span!(
                            "step-teardown-realize",
                            job = job.name,
                            step = step.name,
                            r#type = "step-teardown-realize",
                        );
                        builder
                            .copy_derivations(&job.name, &[teardown_drv.clone()], &receiver)
                            .await?;
                        let teardown = builder.realize_derivation(teardown_drv, &receiver).await?;
                        builder.fetch_derivation(&teardown, &receiver).await?;
                        Some(teardown)
                    } else {
                        None
                    };
                    let run = {
                        let _span = tracing::debug_span!(
                            "step-run-realize",
                            job = job.name,
                            step = step.name,
                            r#type = "step-run-realize",
                        );
                        builder
                            .copy_derivations(&job.name, &[step.run_drv.clone()], &receiver)
                            .await?;
                        let run = builder.realize_derivation(&step.run_drv, &receiver).await?;
                        builder.fetch_derivation(&run, &receiver).await?;
                        run
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

        let (_guard, receiver, runner) = match local_builder.get_runner(&job).await? {
            Some(RunnerGuard {
                lock: guard,
                receiver,
                builder: runner,
            }) => (guard, receiver, runner),
            None => {
                return Err(JobError::NoMatchingRunners {
                    job_name: job.name.clone(),
                    host_system: job.host_system.clone(),
                    required_system_features: job.required_system_features.clone(),
                });
            }
        };
        if matches!(receiver.try_recv(), Ok(()) | Err(TryRecvError::Closed)) {
            return Err(color_eyre::eyre::eyre!("Runner aborted").into());
        }
        let runner_name = runner.get_name();
        let is_remote = runner.is_remote();
        info!(
            runner = runner_name,
            is_remote, "Running job '{}'...", &job.name
        );

        let (mut checkout_child, cwdir) = runner.checkout(job.checkout)?;

        let mut teardown_stack = Vec::new();

        let steps_fut = async {
            if let Some(checkout_child) = checkout_child.as_mut() {
                smol::future::race(
                    async {
                        let _ = receiver.recv().await;
                        Err(color_eyre::eyre::eyre!("Runner aborted"))
                    },
                    checkout_child.run(),
                )
                .await?;
            }

            runner
                .copy_derivations(&job.name, &derivations, &receiver)
                .await?;

            for (step, run, teardown) in steps {
                let _span = tracing::debug_span!(
                    "step-run",
                    job = job.name,
                    step = step.name,
                    r#type = "step-run",
                );
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
                runner.download(&downloads, &receiver).await?;

                if let Some(teardown) = teardown {
                    teardown_stack.push((step.name.clone(), teardown, step.env.clone()));
                }

                let mut child = runner.run_derivation(
                    &cwdir,
                    self.generate_env_vars_for_step(&step.env)?,
                    run,
                )?;
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

                let exit_status = smol::future::zip(child.status(), log_task).await.0?;

                if !exit_status.success() {
                    return Err(color_eyre::eyre::eyre!(
                        "Step '{}' failed ({})",
                        &step.name,
                        exit_status
                    ));
                }

                if let Some(upload_key) = step.upload_key.as_ref() {
                    let mut buf = Vec::new();
                    stdout.read_to_end(&mut buf).await?;
                    let upload_path = PathBuf::from(OsStr::from_bytes(buf.trim_ascii()));
                    runner.fetch_derivation(&upload_path, &receiver).await?;
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
                        .insert(upload_key.to_string(), upload_path);
                }
            }
            Ok(())
        };

        let mut result: Result<(), JobError> = smol::future::or(steps_fut, async {
            if let Some(timeout) = job.timeout {
                smol::Timer::after(timeout.into()).await;
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
            let _span = tracing::debug_span!(
                "step-teardown",
                job = job.name,
                step = step_name,
                r#type = "step-teardown",
            );

            let env_vars = match self.generate_env_vars_for_step(&step_env) {
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
                    result = result.and_then(|_| {
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
            let mut child = runner.run_derivation(&cwdir, env_vars, teardown)?;
            let stderr = child.stderr.take().expect("stderr is piped");

            let mut lines = BufReader::new(stderr).lines();
            while let Some(line) = lines.next().await {
                if let Ok(line) = line {
                    info!(
                        runner = runner_name,
                        is_remote,
                        step = step_name,
                        teardown = true,
                        "{}",
                        line
                    );
                } else {
                    break;
                }
            }

            let exit_status = match child.status().await {
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
                    result = result.and_then(|_| {
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
                    runner = runner_name,
                    is_remote,
                    step = step_name,
                    teardown = true,
                    "Teardown failed ({}); continuing",
                    exit_status
                );
                result = result.and_then(|_| {
                    Err(color_eyre::eyre::eyre!(
                        "Teardown for step '{}' failed ({})",
                        step_name,
                        exit_status
                    )
                    .into())
                });
            }
        }

        drop(checkout_child.take());
        result.and(
            runner
                .undo_checkout(job.checkout, &cwdir)
                .await
                .map_err(Into::into),
        )
    }

    pub(crate) fn run_job_single<'a>(
        &'a self,
        local_builder: &'a LocalBuilder,
        job: NowJob,
        node_index: NodeIndex<u32>,
    ) -> JobFut<'a> {
        Box::pin(async move {
            let result = self.run_job(local_builder, job).await;
            (node_index, result)
        })
    }

    pub(crate) fn run_jobs_multiple<'a>(
        &'a self,
        local_builder: &'a LocalBuilder,
        jobs: Vec<NowJob>,
        node_index: NodeIndex<u32>,
    ) -> JobFut<'a> {
        let mut fail_fast = FuturesUnordered::new();
        let mut no_fail_fast = FuturesUnordered::new();

        for job in jobs {
            if job
                .strategy
                .as_ref()
                .is_none_or(|strategy| strategy.fail_fast)
            {
                fail_fast.push(self.run_job(local_builder, job));
            } else {
                no_fail_fast.push(self.run_job(local_builder, job));
            }
        }

        Box::pin(async move {
            let (fail_fast, no_fail_fast) = smol::future::zip(
                async move {
                    while let Some(future) = fail_fast.next().await {
                        if future.is_err() {
                            return future;
                        }
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
