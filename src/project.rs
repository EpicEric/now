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
    env::temp_dir,
    path::{Path, PathBuf},
};

use flate2::read::GzDecoder;
use tar::Archive;

use crate::utils::get_random_string;

static PROJECT_ARCHIVE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/project.tar.gz"));

#[derive(Debug, Clone)]
pub(crate) struct ProjectSource(PathBuf);

impl AsRef<Path> for ProjectSource {
    fn as_ref(&self) -> &Path {
        &self.0
    }
}

impl Drop for ProjectSource {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

pub(crate) fn create_nix_project_source() -> color_eyre::Result<ProjectSource> {
    let project_source = ProjectSource(temp_dir().join(format!("now-{}", get_random_string(10))));

    let tar = GzDecoder::new(PROJECT_ARCHIVE);
    let mut archive = Archive::new(tar);
    archive.unpack(&project_source.0)?;

    Ok(project_source)
}
