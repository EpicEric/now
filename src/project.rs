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
    env::temp_dir,
    fs::remove_dir_all,
    path::{Path, PathBuf},
};

use flate2::read::GzDecoder;
use tar::Archive;

use crate::utils::get_random_string;

const PROJECT_ARCHIVE: &[u8] = {
    if option_env!("NOW_PROJECT_SOURCE").is_some() {
        b""
    } else {
        include_bytes!(concat!(env!("OUT_DIR"), "/project.tar.gz"))
    }
};

#[derive(Debug, Clone)]
pub(crate) struct ProjectSource {
    directory: PathBuf,
    in_nix_store: bool,
}

impl AsRef<Path> for ProjectSource {
    fn as_ref(&self) -> &Path {
        &self.directory
    }
}

impl Drop for ProjectSource {
    fn drop(&mut self) {
        if !self.in_nix_store {
            let _ = remove_dir_all(&self.directory);
        }
    }
}

impl ProjectSource {
    pub(crate) fn new() -> color_eyre::Result<Self> {
        if let Some(project_source) = option_env!("NOW_PROJECT_SOURCE") {
            return Ok(ProjectSource {
                directory: PathBuf::from(project_source),
                in_nix_store: true,
            });
        }

        let project_source = ProjectSource {
            directory: temp_dir().join(format!("now-{}", get_random_string(10))),
            in_nix_store: false,
        };

        let tar = GzDecoder::new(PROJECT_ARCHIVE);
        let mut archive = Archive::new(tar);
        archive.unpack(&project_source.directory)?;

        Ok(project_source)
    }
}
