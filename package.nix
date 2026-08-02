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
  bubblewrap,
  installShellFiles,
  lib,
  makeWrapper,
  nix,
  openssh,
  rsync,
  rustPlatform,
  stdenv,
}:
rustPlatform.buildRustPackage {
  pname = "now";
  version = (lib.importTOML ./Cargo.toml).package.version;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./.tack
      ./nix
      ./now-step
      ./src
      ./build.rs
      ./Cargo.toml
      ./Cargo.lock
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  strictDeps = true;
  __structuredAttrs = true;

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];

  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/now \
      --suffix PATH : ${
        lib.makeBinPath (
          [
            nix
            openssh
            rsync
          ]
          ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ]
        )
      }
  ''
  + lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd now \
      --bash <(COMPLETE=bash $out/bin/now) \
      --fish <(COMPLETE=fish $out/bin/now) \
      --zsh <(COMPLETE=zsh $out/bin/now)
  '';

  meta = {
    name = "now";
    description = "Nix-based distributed command runner";
    homepage = "https://now.dev.br";
    license = lib.licenses.agpl3Plus;
    mainProgram = "now";
    platforms = lib.platforms.all;
  };
}
