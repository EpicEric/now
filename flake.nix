# now: Nix-based distributed command runner
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
  description = "Nix-based distributed command runner";

  inputs = { };

  outputs =
    { self, ... }@args:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem =
        f:
        (builtins.foldl' (
          acc: system:
          let
            fSystem = f system;
          in
          builtins.foldl' (
            acc': attr:
            acc'
            // {
              ${attr} = (acc'.${attr} or { }) // fSystem.${attr};
            }
          ) acc (builtins.attrNames fSystem)
        ) { } systems);

      inputs = import ./.tack {
        overrides = args.tackOverrides or { };
      };
    in
    eachSystem (
      system:
      let
        pkgs = import inputs.nixpkgs { inherit system; };
        inherit
          (import ./nix {
            inherit system pkgs;
          })
          now
          now-step
          shell
          ;
      in
      {
        packages.${system} = {
          default = now;
          inherit now now-step;
        };

        apps.${system}.default = {
          type = "app";
          program = pkgs.lib.getExe now;
          inherit (now) meta;
        };

        devShells.${system}.default = shell;
      }
    );
}
