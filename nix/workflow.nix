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
  nixpkgs ? <nixpkgs>,
  pkgs ? import nixpkgs { inherit system; },
}:

let
  inherit (pkgs) lib;
  types = import ./types.nix { inherit lib; };

  mkNowStep = pkgs: (import ./. { inherit pkgs; }).now-step;

  normalizeJob =
    job: evalId:
    (lib.evalModules {
      modules = [
        { options.__job = lib.mkOption { type = types.job evalId; }; }
        { __job = job; }
      ];
    }).config.__job;

  mapMaybeList =
    fn: job': evalId:
    if builtins.isList job' then
      map (
        e:
        fn {
          job = normalizeJob e.job evalId;
          pkgs' = e.pkgs' or pkgs;
          requiredSystemFeatures = e.requiredSystemFeatures or [ ];
        }
      ) job'
    else
      fn {
        job = normalizeJob (
          if lib.isFunction job' then
            job' {
              inherit pkgs;
              inherit (pkgs) lib;
            }
          else
            job'
        ) evalId;
        pkgs' = pkgs;
        requiredSystemFeatures = [ ];
      };

  stepFnInner =
    {
      placeholder_name,
      pkgs,
      jobEnv,
      step,
      evalId,
    }:
    let
      inherit (pkgs)
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
    in
    {
      name = if (step.name != null && step.name != "") then step.name else placeholder_name;

      runDrv =
        (writeShellApplication {
          name = "now-step";
          runtimeInputs = step.path ++ [ (mkNowStep pkgs) ];
          text = ''
            now-step ${
              if step."__nowUpload_${evalId}" == null then "" else "--preserve-stdout"
            } ${script step.run} ${
              builtins.concatStringsSep " " (
                map lib.strings.escapeShellArg (
                  builtins.attrNames (
                    builtins.mapAttrs (_: value: value."__nowSecret_${evalId}") (
                      lib.filterAttrs (_: value: value ? "__nowSecret_${evalId}") env
                    )
                  )
                )
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
            runtimeInputs = step.path ++ [ (mkNowStep pkgs) ];
            text = ''
              now-step ${script step.teardown} ${
                builtins.concatStringsSep " " (
                  map lib.strings.escapeShellArg (
                    builtins.attrNames (
                      builtins.mapAttrs (_: value: value."__nowSecret_${evalId}") (
                        lib.filterAttrs (_: value: value ? "__nowSecret_${evalId}") env
                      )
                    )
                  )
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
      step,
      evalId,
    }:
    if step == null then
      null
    else
      let
        step' =
          (lib.evalModules {
            modules = [
              { options.__step = lib.mkOption { type = types.step evalId; }; }
              { __step = if lib.isFunction step then step { inherit pkgs lib; } else step; }
            ];
          }).config.__step;
      in
      stepFnInner {
        inherit
          placeholder_name
          pkgs
          jobEnv
          evalId
          ;
        step = step';
      };

  nowConfig =
    evalId: module:
    module.config
    // {
      jobs = builtins.mapAttrs (
        jobKey: job':
        mapMaybeList (
          {
            job,
            pkgs',
            requiredSystemFeatures,
          }:
          assert lib.assertMsg (builtins.all (
            x: lib.isString x
          ) requiredSystemFeatures) "requiredSystemFeatures argument must be a list of strings";
          job
          // {
            name = if (job.name != null && job.name != "") then job.name else jobKey;
            buildSystem = pkgs'.stdenv.buildPlatform.system;
            hostSystem = pkgs'.stdenv.hostPlatform.system;
            inherit requiredSystemFeatures;
            steps = lib.imap0 (
              i: step:
              stepFn {
                inherit step;
                placeholder_name = "${jobKey}-${toString i}";
                pkgs = pkgs';
                jobEnv = job.env;
                inherit evalId;
              }
            ) job.steps;
          }
        ) job' evalId
      ) module.config.jobs;
    };

  nowModule =
    { lib, ... }:
    let
      inherit (lib) types;
    in
    {
      options = {
        name = lib.mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Name of the workflow";
        };
        default = lib.mkOption {
          type = types.nullOr (types.listOf types.str);
          default = null;
          description = "Default jobs to run for this workflow";
        };
        jobs = lib.mkOption {
          type = types.attrsOf (types.nullOr types.raw);
          description = "Jobs in the workflow.";
        };
      };
    };
in

workflow:
{
  evalId,
  vars ? { },
  var ?
    name:
    assert lib.assertMsg (lib.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    vars.${name} or "",
}:
let
  secret =
    name:
    assert lib.assertMsg (lib.isValidPosixName name)
      "environment variable '${name}' is not a valid POSIX variable name";
    {
      ${"__nowSecret_${evalId}"} = name;
    };
in
nowConfig evalId (
  lib.evalModules {
    class = "now";
    modules = [
      nowModule
      workflow
    ];
    specialArgs = {
      runner = {
        inherit secret var;

        matrix =
          variants: job':
          map (v: {
            job =
              if lib.isFunction job' then
                job' (
                  {
                    inherit pkgs;
                    inherit (pkgs) lib;
                  }
                  // v
                )
              else
                job';
            pkgs' = v.pkgs or pkgs;
            requiredSystemFeatures = v.requiredSystemFeatures or [ ];
          }) variants;

        steps = {
          build =
            name: deriv:
            assert lib.assertMsg (lib.isDerivation deriv)
              "derivation argument to runner.steps.build must be a derivation";
            { pkgs, ... }: {
              name = "build ${if name == "" then deriv.name else name}";
              path = [ pkgs.nix ];
              run = ''
                drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
                nix-store --realise "$drv" >/dev/null
                printf 'now: Built %s\n' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
              '';
            };

          upload =
            name: deriv:
            assert lib.assertMsg (name != "") "name argument to runner.steps.upload must not be empty";
            assert lib.assertMsg (lib.isDerivation deriv)
              "derivation argument to runner.steps.upload must be a derivation";
            { pkgs, ... }: {
              name = "upload ${name}";
              path = [ pkgs.nix ];
              run = ''
                drv=${builtins.unsafeDiscardOutputDependency deriv.drvPath}
                nix-store --realise "$drv" >/dev/null
                printf '%s' ${lib.escapeShellArg (builtins.unsafeDiscardStringContext deriv.outPath)}
              '';
              ${"__nowUpload_${evalId}"} = name;
            };
        };

        download = name: {
          ${"__nowDownload_${evalId}"} = name;
        };
      };
    };
  }
)
