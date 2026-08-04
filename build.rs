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
    fs::File,
    path::{Path, PathBuf},
};

use flate2::write::GzEncoder;
use tar::Builder;

fn main() {
    let out_dir = std::env::var_os("OUT_DIR").expect("OUT_DIR is set");
    let archive_path = Path::new(&out_dir).join("project.tar.gz");

    let file = File::create(&archive_path).expect("should create archive in OUT_DIR");
    let tar_gz = GzEncoder::new(file, Default::default());
    let mut tar = Builder::new(tar_gz);

    for dir in ["nix", "now-step", ".tack"] {
        let dir_path = PathBuf::from(dir);
        for result in ignore::Walk::new(&dir_path) {
            if let Ok(dir_entry) = result
                && dir_entry
                    .file_type()
                    .is_some_and(|file_type| file_type.is_file())
            {
                let file_path = dir_entry.path();
                tar.append_file(
                    &file_path,
                    &mut std::fs::File::open(&file_path).expect("file should be readable"),
                )
                .expect("should write file to archive");
            }
        }
    }

    tar.finish().expect("should flush archive");

    println!("cargo:rerun-if-changed=nix");
    println!("cargo:rerun-if-changed=now-step");
    println!("cargo:rerun-if-changed=.tack");
}
