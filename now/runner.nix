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
  evalId,
  overlay,
  var,
}:

{ pkgs }:

let
  inherit (pkgs) lib;

  nixConfigToEnv =
    nixConfig:
    let
      mergedNixConfig = nixConfig // {
        experimental-features = lib.lists.uniqueStrings (
          [
            "nix-command"
            "flakes"
          ]
          ++ (nixConfig.experimental-features or [ ])
        );
      };
    in
    {
      NIX_CONFIG =
        let
          mkValueString =
            v:
            if v == null then
              ""
            else if lib.isInt v then
              toString v
            else if lib.isBool v then
              lib.boolToString v
            else if lib.isFloat v then
              lib.strings.floatToString v
            else if lib.isDerivation v then
              toString v
            else if builtins.isPath v then
              toString v
            else if lib.isString v then
              v
            else if lib.strings.isConvertibleWithToString v then
              toString v
            else
              abort "The Nix config value '${lib.toPretty { } v}' cannot be encoded";
          mkKeyValue = k: v: "${lib.escape [ "=" ] k} = ${mkValueString v}";
          mkKeyValuePairs = attrs: lib.concatStringsSep "\n" (lib.mapAttrsToList mkKeyValue attrs);
          isExtra = key: lib.hasPrefix "extra-" key;
        in
        lib.trim ''
          ${mkKeyValuePairs (lib.filterAttrs (key: _: !(isExtra key)) mergedNixConfig)}
          ${mkKeyValuePairs (lib.filterAttrs (key: _: isExtra key) mergedNixConfig)}
        '';
    };
in

{
  inherit var;

  secret =
    name:
    assert lib.assertMsg (lib.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    {
      ${"__nowSecret_${evalId}"} = name;
    };

  download = name: {
    ${"__nowDownload_${evalId}"} = name;
  };

  matrix =
    variants: job:
    map (variant: {
      inherit job;
      pkgs = if variant ? pkgs then variant.pkgs.extend overlay else pkgs;
      specialArgs = removeAttrs variant [
        "pkgs"
        "requiredSystemFeatures"
      ];
      requiredSystemFeatures = variant.requiredSystemFeatures or [ ];
    }) variants;

  steps = {
    build =
      {
        name ? "",
        deriv,
        nixConfig ? { },
        env ? { },
        sandbox ? { },
      }:
      assert lib.assertMsg (lib.isDerivation deriv)
        "deriv argument to runner.steps.build must be a derivation";
      { pkgs, ... }: {
        name = "build ${if name == "" then deriv.name else name}";
        path = [
          pkgs.nix
          pkgs.mktemp
        ];
        env = (nixConfigToEnv nixConfig) // env;
        sandbox = sandbox // {
          writableNixStore = true;
          networkAccess = true;
          gcroots = true;
        };
        run = ''
          set -euo pipefail
          export NOW_GCROOT_DIR="''${NOW_GCROOT_DIR:-$(mktemp -d)}"
          mkdir -p "$NOW_GCROOT_DIR"
          drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
          nix-store --add-root "$NOW_GCROOT_DIR/''${drv##*/}" --indirect --realise "$drv" >/dev/null
          printf "now: Built '%s' (%s)\n" ${
            lib.escapeShellArg (if name == "" then deriv.name else name)
          } ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
        '';
      };

    upload =
      {
        name,
        deriv,
        nixConfig ? { },
        env ? { },
        sandbox ? { },
      }:
      assert lib.assertMsg (name != "") "name argument to runner.steps.upload must not be empty";
      assert lib.assertMsg (lib.isDerivation deriv)
        "deriv argument to runner.steps.upload must be a derivation";
      { pkgs, ... }: {
        name = "upload ${name}";
        path = [
          pkgs.nix
          pkgs.mktemp
        ];
        env = (nixConfigToEnv nixConfig) // env;
        sandbox = {
          writableNixStore = true;
          networkAccess = true;
          gcroots = true;
        }
        // sandbox;
        run = ''
          set -euo pipefail
          export NOW_GCROOT_DIR="''${NOW_GCROOT_DIR:-$(mktemp -d)}"
          mkdir -p "$NOW_GCROOT_DIR"
          drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
          nix-store --add-root "$NOW_GCROOT_DIR/''${drv##*/}" --indirect --realise "$drv" >/dev/null
          printf '%s' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
        '';
        ${"__nowUpload_${evalId}"} = name;
      };

    tempdir = name: { pkgs, ... }: {
      name = "create tempdir";
      path = [ pkgs.mktemp ];
      sandbox.enable = false;
      run = ''
        set -euo pipefail
        mktemp -d
      '';
      teardown = ''
        DIR_TO_REMOVE=''$${name}
        if [ -d $DIR_TO_REMOVE ]; then
          rm -rf $DIR_TO_REMOVE
        fi
      '';
      outputVar = name;
    };
  };
}
