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
  system ? builtins.currentSystem,
  inputs ? import ../.tack,
  pkgs ? import inputs.nixpkgs { inherit system; },
  useCache ? false,
}:
let
  inherit (pkgs) lib;

  now = pkgs.callPackage ../package.nix { };
  now-step = pkgs.callPackage ../now-step/package.nix (
    lib.optionalAttrs useCache { optimizeLevel = "ReleaseSafe"; }
  );
in
{
  inherit now now-step;

  shell = pkgs.mkShell {
    packages = [
      pkgs.cargo
      pkgs.clippy
      pkgs.rust-analyzer
      pkgs.rustc
      pkgs.rustfmt
      pkgs.zig_0_16
    ];
  };
}
