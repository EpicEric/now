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
    collections::HashMap,
    ffi::OsString,
    path::{Path, PathBuf},
    pin::Pin,
};

use smol::{channel, lock::futures::Lock, process::Child};

use async_trait::async_trait;
use serde::Deserialize;

use crate::utils::pipe_outputs_to_stderr;

pub(crate) mod local;
pub(crate) mod remote;

pub(crate) trait CheckoutTask {
    fn run<'a>(&'a mut self) -> Pin<Box<dyn Future<Output = color_eyre::Result<()>> + 'a>>;
}

pub(crate) static CACHE_SUBSTITUTER: &str = "https://cache.eric.dev.br";
pub(crate) static CACHE_PUBLIC_KEY: &str =
    "cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=";

struct CommandCheckoutTask {
    pub(crate) builder: String,
    pub(crate) child: Child,
}

impl Drop for CommandCheckoutTask {
    fn drop(&mut self) {
        let _ = self.child.kill();
    }
}

impl CheckoutTask for CommandCheckoutTask {
    fn run<'a>(
        &'a mut self,
    ) -> std::pin::Pin<Box<dyn Future<Output = color_eyre::Result<()>> + 'a>> {
        Box::pin(async {
            let status = self.child.status().await?;
            if status.success() {
                Ok(())
            } else {
                pipe_outputs_to_stderr(&mut self.child).await?;
                Err(color_eyre::eyre::eyre!(
                    "Failed to checkout current directory to {}",
                    self.builder
                ))
            }
        })
    }
}

#[async_trait(?Send)]
pub(crate) trait NowBuilder {
    fn acquire(&self) -> Lock<'_, channel::Receiver<()>>;

    fn get_name(&self) -> String;

    fn is_remote(&self) -> bool;

    fn checkout(&self) -> color_eyre::Result<(Option<Box<dyn CheckoutTask>>, PathBuf)>;

    async fn copy_derivations(
        &self,
        job_name: &str,
        derivations: &[PathBuf],
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()>;

    async fn realize_derivation(
        &self,
        derivation: &Path,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<PathBuf>;

    async fn download(
        &self,
        downloads: &[PathBuf],
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()>;

    fn run_derivation(
        &self,
        cwdir: &Path,
        derivation: PathBuf,
        envs: HashMap<OsString, OsString>,
    ) -> color_eyre::Result<Child>;

    async fn fetch_derivation(
        &self,
        derivation: &Path,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()>;

    async fn undo_checkout(&self, path: &Path) -> color_eyre::Result<()>;
}

#[derive(Deserialize, Debug)]
pub(crate) struct NixConfigValue<T> {
    value: T,
}

#[derive(Deserialize, Debug)]
pub(crate) struct NixConfig {
    builders: NixConfigValue<String>,
    #[serde(rename = "extra-platforms")]
    extra_platforms: NixConfigValue<Vec<String>>,
    system: NixConfigValue<String>,
    #[serde(rename = "system-features")]
    system_features: NixConfigValue<Vec<String>>,
}
