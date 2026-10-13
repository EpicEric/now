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

use std::path::{Path, PathBuf};

use smol::{
    channel,
    lock::futures::{Acquire, Read, Write},
    process::Child,
};

use async_trait::async_trait;
use serde::Deserialize;

use crate::workflow::NowCheckout;

pub(crate) mod local;
pub(crate) mod remote;

#[async_trait(?Send)]
pub(crate) trait NowBuilder {
    fn acquire(&self) -> (Acquire<'_>, Read<'_, ()>, &channel::Receiver<()>);

    fn acquire_exclusive(&self) -> (Write<'_, ()>, &channel::Receiver<()>);

    fn get_name(&self) -> String;

    fn is_remote(&self) -> bool;

    async fn create_tempdir(
        &self,
        checkout: NowCheckout,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<Option<PathBuf>>;

    async fn checkout(
        &self,
        checkout: NowCheckout,
        tempdir: Option<PathBuf>,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<PathBuf>;

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

    fn run_derivation(&self, cwdir: &Path, derivation: PathBuf) -> color_eyre::Result<Child>;

    async fn fetch_derivation(
        &self,
        derivation: &Path,
        cancellation: &channel::Receiver<()>,
    ) -> color_eyre::Result<()>;

    async fn undo_checkout(&self, checkout: NowCheckout, path: &Path) -> color_eyre::Result<()>;
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
