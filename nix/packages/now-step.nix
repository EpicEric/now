# now: A Nix-based distributed command runner
# Copyright (C) 2026 Eric Rodrigues Pires
#
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, either version 3 of the License, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
# more details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.

{
  lib,
  rustPlatform,
  src,
}:
rustPlatform.buildRustPackage {
  pname = "now-step";
  version = (lib.importTOML ../../now-step/Cargo.toml).package.version;

  inherit src;
  cargoLock.lockFile = ../../Cargo.lock;

  buildAndTestSubdir = "now-step";

  strictDeps = true;
  __structuredAttrs = true;

  doCheck = false;

  meta = {
    name = "now-step";
    description = "Nix-based distributed command runner";
    homepage = "https://github.com/EpicEric/now";
    license = lib.licenses.agpl3Plus;
    mainProgram = "now-step";
    platforms = lib.platforms.all;
  };
}
