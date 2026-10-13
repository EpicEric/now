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
  system ? builtins.currentSystem,
  withLocalStep ? false,
}:

let
  inputs = import ../.tack;

  overlay =
    _: prev:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      local-now-step = pkgs.callPackage ../now-step/package.nix { };
    in
    {
      now-step = if withLocalStep then local-now-step else prev.now-step or local-now-step;
    };

  evalModule =
    {
      lib,
      specialArgs ? { },
      module,
      args,
    }:
    let
      evaledArgs =
        if lib.isFunction args then
          args (builtins.intersectAttrs (lib.functionArgs args) (specialArgs // { inherit lib; }))
        else
          args;
    in
    if evaledArgs == null then null else removeAttrs (module evaledArgs) [ "__functor" ];
in

{
  workflow,
  evalId,
  lib' ? import <nixpkgs/lib>,
  vars ? { },
  var ?
    name:
    assert lib'.assertMsg (lib'.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    vars.${name} or "@@__nowUnset_${evalId}_${name}@@",
}:

let
  adios = import inputs.adios;

  adiosArgs = adios // {
    inherit evalId evalModule;
    envType =
      let
        inherit (adios) types;
      in
      types.attrsOf (
        types.either types.string (
          types.either
            (types.struct "nowSecret" {
              ${"__nowSecret_${evalId}"} = types.string;
            })
            (
              types.struct "nowDownload" {
                ${"__nowDownload_${evalId}"} = types.string;
              }
            )
        )
      );
  };

  runnerFn = import ./runner.nix { inherit evalId overlay var; };

  workflow' = if builtins.isPath workflow then import workflow else workflow;

  pkgs = import (workflow'.nixpkgs or <nixpkgs>) {
    inherit system;
    overlays = [ overlay ];
  };
in

evalModule {
  inherit (pkgs) lib;
  module =
    ((import ./modules adiosArgs) {
      options = {
        "/workflow/nixpkgs" = {
          inherit pkgs;
        };
        "/workflow/workflowInputs" = {
          inherit overlay;
        };
      };
    }).modules.workflow;
  specialArgs = {
    runner = runnerFn { inherit pkgs; };
  };
  args = workflow';
}
