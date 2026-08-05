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
    collections::{HashMap, HashSet},
    env::temp_dir,
    ffi::{OsStr, OsString},
    io::Write,
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
};

use async_trait::async_trait;
use futures::{AsyncWriteExt, stream::FuturesUnordered};
use smol::{
    channel::{self, Receiver},
    io::AsyncReadExt,
    lock::{Mutex, MutexGuard, futures::Lock},
    process::{Child, Command, Stdio},
    stream::StreamExt,
};

use crate::{
    builder::{
        CACHE_PUBLIC_KEY, CACHE_SUBSTITUTER, CheckoutTask, CommandCheckoutTask, NixConfig,
        NowBuilder, RsyncCheckoutTask, remote::RemoteBuilder,
    },
    environment::NowEnvironment,
    utils::{get_random_string, pipe_outputs_to_stderr},
    workflow::{NowCheckout, NowJob},
};

pub(crate) struct LocalBuilder {
    pub(crate) cancellation: channel::Sender<()>,
    pub(crate) cancellation_rx: Mutex<channel::Receiver<()>>,
    pub(crate) env: HashMap<OsString, OsString>,
    pub(crate) use_cache: bool,
    pub(crate) hostname: String,
    pub(crate) extra_platforms: Vec<String>,
    pub(crate) system: String,
    pub(crate) system_features: HashSet<String>,
    pub(crate) remote_builders: Vec<RemoteBuilder>,
    pub(crate) remote_only: bool,
}

impl LocalBuilder {
    pub(crate) fn new(
        environment: &NowEnvironment,
        use_cache: bool,
        builders: Option<String>,
        local_only: bool,
        remote_only: bool,
    ) -> color_eyre::Result<Self> {
        let output = std::process::Command::new("nix")
            .args([
                "--extra-experimental-features",
                "nix-command flakes",
                "config",
                "show",
                "--json",
            ])
            .output()?;

        if !output.status.success() {
            let mut stderr = std::io::stderr();
            stderr.write_all(&output.stderr)?;
            stderr.flush()?;
            return Err(color_eyre::eyre::eyre!("Failed to fetch Nix config"));
        }

        let config: NixConfig = serde_json::from_slice(&output.stdout)?;

        let remote_builders = if local_only {
            vec![]
        } else {
            RemoteBuilder::get_remote_builders(
                &config,
                use_cache,
                builders,
                environment.nix_project_source.as_ref(),
            )?
        };
        if remote_only && remote_builders.is_empty() {
            return Err(color_eyre::eyre::eyre!("No remote builders available"));
        }

        let (cancellation, cancellation_rx) = channel::bounded(1);

        let hostname = nix::unistd::gethostname()?.to_string_lossy().into_owned();

        Ok(Self {
            cancellation,
            cancellation_rx: Mutex::new(cancellation_rx),
            env: environment.local_env.clone(),
            use_cache,
            hostname,
            extra_platforms: config.extra_platforms.value,
            system: config.system.value,
            system_features: config.system_features.value.into_iter().collect(),
            remote_builders,
            remote_only,
        })
    }

    pub(crate) fn cancel_builders(&self) {
        self.cancellation.close();
        for remote in &self.remote_builders {
            remote.cancellation.close();
        }
    }

    pub(crate) async fn get_builder(
        &self,
        job: &NowJob,
    ) -> color_eyre::Result<Option<(MutexGuard<'_, Receiver<()>>, &dyn NowBuilder)>> {
        let mut builders = vec![];

        if !self.remote_only
            && job.build_system == self.system
            && job
                .required_system_features
                .iter()
                .all(|feature| self.system_features.contains(feature))
        {
            builders.push(self as &dyn NowBuilder);
        }

        for builder in self.remote_builders.iter() {
            if builder.build_systems.contains(&job.build_system)
                && builder
                    .required_features
                    .iter()
                    .all(|feature| job.required_system_features.contains(feature))
                && job
                    .required_system_features
                    .iter()
                    .all(|feature| builder.system_features.contains(feature))
            {
                builders.push(builder as &dyn NowBuilder);
            }
        }

        let mut builders_fut: FuturesUnordered<_> = builders
            .into_iter()
            .map(|builder| async move {
                let guard = builder.acquire().await;
                (guard, builder)
            })
            .collect();

        Ok(builders_fut.next().await)
    }

    pub(crate) async fn get_runner(
        &self,
        job: &NowJob,
    ) -> color_eyre::Result<Option<(MutexGuard<'_, Receiver<()>>, &dyn NowBuilder)>> {
        let mut runners = vec![];

        if !self.remote_only
            && (job.host_system == self.system || self.extra_platforms.contains(&job.host_system))
            && job
                .required_system_features
                .iter()
                .all(|feature| self.system_features.contains(feature))
        {
            runners.push(self as &dyn NowBuilder);
        }

        for builder in self.remote_builders.iter() {
            if builder.host_system == job.host_system
                && builder
                    .required_features
                    .iter()
                    .all(|feature| job.required_system_features.contains(feature))
                && job
                    .required_system_features
                    .iter()
                    .all(|feature| builder.system_features.contains(feature))
            {
                runners.push(builder as &dyn NowBuilder);
            }
        }

        let mut runners_fut: FuturesUnordered<_> = runners
            .into_iter()
            .map(|builder| async move {
                let guard = builder.acquire().await;
                (guard, builder)
            })
            .collect();

        Ok(runners_fut.next().await)
    }
}

#[async_trait(?Send)]
impl NowBuilder for LocalBuilder {
    fn acquire(&self) -> Lock<'_, channel::Receiver<()>> {
        self.cancellation_rx.lock()
    }

    fn get_name(&self) -> String {
        self.hostname.clone()
    }

    fn is_remote(&self) -> bool {
        false
    }

    fn checkout(
        &self,
        checkout: NowCheckout,
    ) -> color_eyre::Result<(Option<Box<dyn CheckoutTask>>, PathBuf)> {
        match checkout {
            NowCheckout::Default => Ok((None, std::env::current_dir()?)),
            NowCheckout::None => {
                let tmpdir = temp_dir().join(format!("now-{}", get_random_string(10)));

                let mut command = Command::new("mkdir");
                command
                    .arg("-p")
                    .arg(&tmpdir)
                    .stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped());

                Ok((
                    Some(Box::new(CommandCheckoutTask {
                        builder: self.get_name(),
                        child: command.spawn()?,
                    })),
                    tmpdir,
                ))
            }
            NowCheckout::Clone => {
                let tmpdir = temp_dir().join(format!("now-{}", get_random_string(10)));

                let mut command = Command::new("rsync");
                command
                    .args(["-arz", "--files-from=-", "."])
                    .arg(&tmpdir)
                    .stdin(Stdio::piped())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped());

                let mut child = command.spawn()?;
                let mut stdin = child.stdin.take().expect("stdin is piped");
                let stdin_future = Box::pin(async move {
                    let cwd = std::env::current_dir()?;
                    for dir_entry in ignore::Walk::new(std::env::current_dir()?).flatten() {
                        if dir_entry.file_type().is_some_and(|typ| typ.is_file()) {
                            let path = dir_entry.path();
                            stdin
                                .write_all(
                                    path.strip_prefix(&cwd)
                                        .unwrap_or(path)
                                        .as_os_str()
                                        .as_bytes(),
                                )
                                .await?;
                            stdin.write_all(b"\n").await?;
                        }
                    }
                    Ok(stdin.flush().await?)
                });

                Ok((
                    Some(Box::new(RsyncCheckoutTask {
                        builder: self.get_name(),
                        child,
                        stdin_future,
                    })),
                    PathBuf::from(tmpdir),
                ))
            }
        }
    }

    async fn copy_derivations(
        &self,
        _job_name: &str,
        _derivations: &[PathBuf],
        _cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()> {
        Ok(())
    }

    async fn realize_derivation(
        &self,
        derivation: &Path,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<PathBuf> {
        let mut command = Command::new("nix-store");
        if self.use_cache {
            command.args([
                "--option",
                "extra-substituters",
                CACHE_SUBSTITUTER,
                "--option",
                "extra-trusted-public-keys",
                CACHE_PUBLIC_KEY,
            ]);
        }
        command
            .arg("--realise")
            .arg(derivation)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        let mut child = command.spawn()?;
        let result = smol::future::race(
            async {
                let _ = cancellation.recv().await;
                Err(color_eyre::eyre::eyre!("Runner aborted"))
            },
            async {
                if child.status().await?.success() {
                    let mut stdout = child.stdout.take().expect("stdout is piped");
                    let mut buf = Vec::new();
                    stdout.read_to_end(&mut buf).await?;
                    Ok(PathBuf::from(OsStr::from_bytes(buf.trim_ascii())))
                } else {
                    pipe_outputs_to_stderr(&mut child).await?;
                    Err(color_eyre::eyre::eyre!(
                        "Failed to realize derivation '{}'",
                        derivation.to_string_lossy(),
                    ))
                }
            },
        )
        .await;
        let _ = child.kill();
        result
    }

    async fn download(
        &self,
        _downloads: &[PathBuf],
        _cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()> {
        Ok(())
    }

    fn run_derivation(
        &self,
        cwdir: &Path,
        envs: HashMap<OsString, OsString>,
        derivation: PathBuf,
    ) -> color_eyre::Result<Child> {
        let mut command = Command::new(derivation.join("bin/now-step"));
        command
            .current_dir(cwdir)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .env_clear()
            .envs(&self.env)
            .envs(envs);
        Ok(command.spawn()?)
    }

    async fn fetch_derivation(
        &self,
        _derivation: &Path,
        _cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()> {
        Ok(())
    }

    async fn undo_checkout(&self, checkout: NowCheckout, path: &Path) -> color_eyre::Result<()> {
        match checkout {
            NowCheckout::Default => Ok(()),
            NowCheckout::None | NowCheckout::Clone => {
                let mut command = Command::new("rm");
                command.arg("-rf").arg(path);

                let mut child = command.spawn()?;
                if child.status().await?.success() {
                    Ok(())
                } else {
                    pipe_outputs_to_stderr(&mut child).await?;
                    Err(color_eyre::eyre::eyre!(
                        "Failed to remove locally checked out directory"
                    ))
                }
            }
        }
    }
}
