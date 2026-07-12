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

use std::{
    collections::HashMap,
    os::unix::ffi::OsStrExt,
    path::{Path, PathBuf},
};

use serde::{Deserialize, Serialize};

use crate::secret::SecretString;

#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct CixEnvironment {
    pub(crate) secrets: HashMap<String, SecretString>,
    pub(crate) vars: HashMap<String, String>,
    #[serde(default)]
    pub(crate) uploads: HashMap<String, PathBuf>,
}

impl CixEnvironment {
    pub(crate) fn get() -> color_eyre::Result<CixEnvironment> {
        match std::env::vars_os().find(|(key, _)| key == "CIX_ENVIRONMENT") {
            Some((_, value)) => Ok(serde_json::from_slice(value.as_bytes())?),
            None => Err(color_eyre::eyre::eyre!("Missing CIX_ENVIRONMENT envvar")),
        }
    }

    pub(crate) fn upload(&mut self, name: String, derivation: PathBuf) -> color_eyre::Result<()> {
        if self.uploads.insert(name, derivation).is_some() {
            Err(color_eyre::eyre::eyre!("Upload key already used"))
        } else {
            Ok(())
        }
    }

    pub(crate) fn download(&self, name: &str) -> Option<&Path> {
        self.uploads.get(name).map(|path| path.as_ref())
    }
}
