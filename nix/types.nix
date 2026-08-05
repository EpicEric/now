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

{ lib }:
let
  inherit (lib) types;

  env =
    { evalId }:
    types.attrsOf (
      types.either types.str (
        types.attrTag {
          ${"__nowSecret_${evalId}"} = lib.mkOption { type = types.str; };
          ${"__nowDownload_${evalId}"} = lib.mkOption { type = types.str; };
        }
      )
    );

  sandbox = types.nullOr (
    types.submodule {
      options = {
        enable = lib.mkOption {
          type = types.bool;
          default = true;
          description = "Whether to use a sandbox for the step.";
        };
        writablePath = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Whether the sandboxed step can write to the checked-out directory.";
        };
        networkAccess = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Whether the sandboxed step has network access.";
        };
        useHome = lib.mkOption {
          type = types.bool;
          default = false;
          description = "Whether the sandboxed step can use the runner user's HOME directory.";
        };
      };
    }
  );

  step =
    {
      evalId,
      pkgs,
      specialArgs ? { },
    }:
    types.submoduleWith {
      specialArgs = specialArgs // {
        inherit pkgs;
        inherit (pkgs) lib;
      };
      shorthandOnlyDefinesConfig = true;
      modules = [
        {
          options = {
            name = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Name of the step.";
            };
            shell = lib.mkOption {
              type = types.nullOr types.package;
              default = null;
              description = "The shell to use for this step.";
            };
            shellArgs = lib.mkOption {
              type = types.nullOr (types.listOf types.str);
              default = null;
              description = "Args passed to the shell used in this step.";
            };
            run = lib.mkOption {
              type = types.str;
              default = "";
              description = "Shell script to run on this step.";
            };
            teardown = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Shell script to run when tearing down this step, after every step, in reverse order.";
            };
            path = lib.mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Packages added to the PATH of the script.";
            };
            env = lib.mkOption {
              type = env { inherit evalId; };
              default = { };
              description = "Environment values to make available to this step.";
            };
            sandbox = lib.mkOption {
              type = sandbox;
              default = null;
              description = "Sandbox configuration for this step.";
            };
            ${"__nowUpload_${evalId}"} = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
          };
        }
      ];
    };

  job =
    {
      evalId,
      pkgs,
      specialArgs ? { },
    }:
    types.submoduleWith {
      specialArgs = specialArgs // {
        inherit pkgs;
        inherit (pkgs) lib;
      };
      shorthandOnlyDefinesConfig = true;
      modules = [
        {
          options = {
            name = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Name of the job.";
            };
            checkout = lib.mkOption {
              type = types.enum [
                "none"
                "default"
                "clone"
              ];
              default = "default";
              description = ''
                Whether to use the runner's current directory (`"default"`),
                always create a fresh copy of the current directory (`"clone"`),
                or run in an empty directory (`"none"`).

                When using `"default"` with remote builders or `"clone"`,
                only non-ignored files are copied over.
              '';
            };
            timeout = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
              description = ''
                How long to run this job for before marking as failed, eg. `"30m"` or `"1h"`.
                By default, jobs can run indefinitely.

                The timer doesn't take step realizations or teardowns into account.
              '';
            };
            strategy = lib.mkOption {
              type = types.nullOr (
                types.submodule {
                  options = {
                    failFast = lib.mkOption {
                      type = types.bool;
                      default = true;
                      description = "Whether a single failing run should cancel the remaining jobs in the matrix.";
                    };
                  };
                }
              );
              default = null;
              description = "How multiple jobs in a matrix should coordinate.";
            };
            needs = lib.mkOption {
              type = types.nullOr (types.either types.str (types.listOf types.str));
              default = null;
              description = "Jobs that must be completed before running this one.";
            };
            env = lib.mkOption {
              type = env { inherit evalId; };
              default = { };
              description = "Environment values to make available to steps in this job.";
            };
            sandbox = lib.mkOption {
              type = sandbox;
              default = null;
              description = "Default sandbox configuration for the steps in this job.";
            };
            steps = lib.mkOption {
              type = types.listOf (types.nullOr types.raw);
              default = [ ];
              description = "Steps to run in this job.";
            };
          };
        }
      ];
    };
in
{
  inherit step job;
}
