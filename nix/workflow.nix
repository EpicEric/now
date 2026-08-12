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
}:

let
  mkNowStep = pkgs: (import ./. { inherit pkgs; }).now-step;

  normalizeJob =
    {
      job,
      evalId,
      pkgs,
      specialArgs ? { },
    }:
    let
      inherit (pkgs) lib;
      types = import ./types.nix { inherit lib; };
    in
    (pkgs.lib.evalModules {
      modules = [
        {
          options.__job = pkgs.lib.mkOption {
            type = types.job {
              inherit evalId specialArgs pkgs;
            };
          };
        }
        { __job = job; }
      ];
    }).config.__job;

  mapMaybeList =
    {
      fn,
      pkgs,
      job',
      evalId,
    }:
    let
      pkgs' = pkgs;
      normalize =
        {
          job,
          pkgs ? pkgs',
          specialArgs ? { },
          requiredSystemFeatures ? [ ],
        }:
        fn {
          job = normalizeJob {
            inherit
              job
              evalId
              pkgs
              specialArgs
              ;
          };
          inherit requiredSystemFeatures;
          inherit pkgs;
        };
    in
    if builtins.isList job' then
      map (
        e:
        normalize {
          inherit (e) job;
          pkgs = e.pkgs or pkgs;
          specialArgs = e.specialArgs or { };
          requiredSystemFeatures = e.requiredSystemFeatures or [ ];
        }
      ) job'
    else
      normalize { job = job'; };

  stepFnInner =
    {
      placeholder_name,
      pkgs,
      jobEnv,
      jobSandbox,
      step,
      evalId,
    }:
    let
      inherit (pkgs)
        lib
        writeShellApplication
        writeTextFile
        ;
      script =
        text:
        writeTextFile {
          name = "now-step-script";
          text = ''
            #! ${lib.getExe (if step.shell == null then pkgs.bash else step.shell)} ${
              lib.optionalString (step.shellArgs != null) (lib.escapeShellArgs step.shellArgs)
            }
            ${text}
          '';
          executable = true;
        };

      env = builtins.mapAttrs (
        name: value:
        assert lib.assertMsg (lib.isValidPosixName name)
          "environment variable '${name}' is not a valid POSIX variable name";
        value
      ) (jobEnv // step.env);

      nowSandbox =
        if lib.isBool step.sandbox then
          (if lib.isBool jobSandbox then { } else jobSandbox) // { enable = step.sandbox; }
        else
          (if lib.isBool jobSandbox then { enable = jobSandbox; } else jobSandbox) // step.sandbox;
    in
    {
      name = if (step.name != null && step.name != "") then step.name else placeholder_name;

      runDrv =
        (writeShellApplication {
          name = "now-step";
          checkPhase = "";
          runtimeInputs = step.path ++ [
            (mkNowStep pkgs)
          ];
          text = ''
            now-step ${if step."__nowUpload_${evalId}" == null then "" else "--preserve-stdout"} ${
              pkgs.callPackage ./sandbox.nix {
                inherit nowSandbox;
                nowScript = script step.run;
              }
            } ${
              lib.escapeShellArgs (
                builtins.attrNames (lib.filterAttrs (_: value: value ? "__nowSecret_${evalId}") env)
              )
            }
          '';
        }).drvPath;

      teardownDrv =
        if step.teardown == null then
          null
        else
          (writeShellApplication {
            name = "now-step";
            checkPhase = "";
            runtimeInputs = step.path ++ [
              (mkNowStep pkgs)
            ];
            text = ''
              now-step ${
                pkgs.callPackage ./sandbox.nix {
                  inherit nowSandbox;
                  nowScript = script step.teardown;
                }
              } ${
                lib.escapeShellArgs (
                  builtins.attrNames (lib.filterAttrs (_: value: value ? "__nowSecret_${evalId}") env)
                )
              }
            '';
          }).drvPath;

      inherit env;

      ${"__nowUpload_${evalId}"} = step."__nowUpload_${evalId}";
    };

  stepFn =
    {
      placeholder_name,
      pkgs,
      jobEnv,
      jobSandbox,
      step,
      evalId,
    }:
    if step == null then
      null
    else
      let
        inherit (pkgs) lib;
        types = import ./types.nix { inherit lib; };
        step' =
          (lib.evalModules {
            modules = [
              { options.__step = lib.mkOption { type = types.step { inherit evalId pkgs; }; }; }
              { __step = step; }
            ];
          }).config.__step;
      in
      stepFnInner {
        inherit
          placeholder_name
          pkgs
          jobEnv
          jobSandbox
          evalId
          ;
        step = step';
      };

  nowConfig =
    {
      evalId,
      pkgs,
      module,
    }:
    let
      inherit (pkgs) lib;
    in
    module.config
    // {
      default =
        if lib.isString module.config.default then [ module.config.default ] else module.config.default;
      jobs = builtins.mapAttrs (
        jobKey: job':
        mapMaybeList {
          fn = (
            {
              job,
              pkgs,
              requiredSystemFeatures,
            }:
            assert lib.assertMsg (builtins.all (
              x: lib.isString x
            ) requiredSystemFeatures) "requiredSystemFeatures argument must be a list of strings";
            job
            // {
              name = if (job.name != null && job.name != "") then job.name else jobKey;
              needs = if lib.isString job.needs then [ job.needs ] else job.needs;
              buildSystem = pkgs.stdenv.buildPlatform.system;
              hostSystem = pkgs.stdenv.hostPlatform.system;
              inherit requiredSystemFeatures;
              steps = lib.imap0 (
                i: step:
                stepFn {
                  inherit step pkgs;
                  placeholder_name = "${jobKey}-${toString i}";
                  jobEnv = job.env;
                  jobSandbox = job.sandbox;
                  inherit evalId;
                }
              ) job.steps;
            }
          );
          inherit pkgs job' evalId;
        }
      ) module.config.jobs;
    };

in

{
  workflow,
  evalId,
  gcrootDir,
  lib' ? import <nixpkgs/lib>,
  vars ? { },
  var ?
    name:
    assert lib'.assertMsg (lib'.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    vars.${name} or "",
}:
let
  secret =
    name:
    assert lib'.assertMsg (lib'.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    {
      ${"__nowSecret_${evalId}"} = name;
    };

  runnerFn =
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
                  abort "The nix conf value: ${lib.toPretty { } v} can not be encoded";
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
      inherit secret var;

      matrix =
        variants: job:
        map (v: {
          inherit job;
          pkgs = v.pkgs or pkgs;
          specialArgs = removeAttrs v [
            "pkgs"
            "requiredSystemFeatures"
          ];
          requiredSystemFeatures = v.requiredSystemFeatures or [ ];
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
            sandbox = {
              writableNixStore = true;
              networkAccess = true;
            }
            // sandbox;
            run = ''
              set -euo pipefail
              drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
              tmpdir=$(mktemp -d ${gcrootDir}/gcroot-XXXXXXXXXX)
              nix-store --add-root $tmpdir/result --realise "$drv" >/dev/null
              printf 'now: Built %s\n' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
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
            }
            // sandbox;
            run = ''
              set -euo pipefail
              drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
              tmpdir=$(mktemp -d ${gcrootDir}/gcroot-XXXXXXXXXX)
              nix-store --add-root $tmpdir/result --realise "$drv" >/dev/null
              printf '%s' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
            '';
            ${"__nowUpload_${evalId}"} = name;
          };
      };

      download = name: {
        ${"__nowDownload_${evalId}"} = name;
      };
    };

  bootstrap = lib'.evalModules {
    class = "now";
    modules = [
      ((import ./types.nix { lib = lib'; }).workflow)
      workflow
    ];
    specialArgs = {
      runner = runnerFn { pkgs = import <nixpkgs> { inherit system; }; };
    };
  };

  pkgs = import bootstrap.config.nixpkgs { inherit system; };
in
nowConfig {
  inherit evalId pkgs;
  module = (
    pkgs.lib.evalModules {
      class = "now";
      modules = [
        ((import ./types.nix { inherit (pkgs) lib; }).workflow)
        workflow
      ];
      specialArgs = {
        runner = runnerFn { inherit pkgs; };
      };
    }
  );
}
