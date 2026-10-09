{
  envType,
  evalModule,
  promise,
  types,
  ...
}@adios:

let
  stepFn =
    {
      placeholderName,
      pkgs,
      jobEnv,
      jobSandbox,
      jobPathLockdown,
      step,
    }:
    if step == null then
      null
    else
      evalModule {
        inherit (pkgs) lib;
        module =
          ((import ./. adios) {
            options = {
              "/step/nixpkgs" = {
                inherit pkgs;
              };
              "/step/stepInputs" = {
                inherit
                  jobEnv
                  jobPathLockdown
                  jobSandbox
                  placeholderName
                  ;
              };
            };
          }).modules.step;
        specialArgs = { inherit pkgs; };
        args = step;
      };
in

{
  inputs = {
    jobInputs.from = { self }: self.jobInputs;
    nixpkgs.from = { self }: self.nixpkgs;
  };

  options = {
    name = {
      type = types.string;
      description = "Name of the job.";
    };
    checkout = {
      type = types.enum "checkoutEnum" [
        "none"
        "default"
        "clone"
        "all"
        "clone-all"
      ];
      default = "default";
      description = ''
        Strategy for checking out the directory that the job runs on.
        Options are:

        - `"default"`- use the runner's current directory.
        - `"clone"` - always create a fresh copy of the current directory.
        - `"none"` - run in an empty directory.
        - `"all"` - same as `"default"`, but ignored files are also copied
        over to remote builders.
        - `"clone-all"` - same as `"clone"`, but ignored files are also copied
        over to remote builders.
      '';
    };
    timeout = {
      type = types.string;
      description = ''
        How long to run this job for before marking as failed, eg. `"30m"` or `"1h"`.
        By default, jobs can run indefinitely.

        The timer doesn't take step realizations or teardowns into account.
      '';
    };
    strategy = {
      type =
        (types.struct "strategy" {
          failFast = types.bool;
        }).override
          { total = false; };
      description = ''
        How multiple jobs in a matrix should coordinate.

        Possible attributes are:

        - `failFast`: Whether a single failing run should cancel the remaining jobs in the matrix.
      '';
    };
    needs = {
      type = types.either types.string (types.listOf types.string);
      description = "Jobs that must be completed before running this one.";
    };
    env = {
      type = envType;
      description = "Environment values to make available to steps in this job.";
    };
    sandbox = {
      type = types.either types.bool types.attrs;
      description = ''
        Default sandbox configuration for the steps in this job.
        See [the submodule documentation](#sandbox).
      '';
    };
    pathLockdown = {
      type = types.bool;
      description = ''
        Whether to lock the script's PATH down to only the packages in each
        steps' `path`, ignoring the calling shell's PATH.
      '';
    };
    steps = {
      type = types.listOf (
        types.nullOr (
          types.new {
            name = "step";
            verify = _: true;
          }
        )
      );
      description = ''
        Steps to run in this job.
        See the [submodule documentation](#step).
      '';
    };
  };

  modules = {
    jobInputs = import ./jobInputs.nix adios;
    nixpkgs = import ./nixpkgs.nix adios;
  };

  result = promise (
    { inputs, options }:
    let
      inherit (inputs.nixpkgs) pkgs;
      inherit (builtins) filter;
      inherit (pkgs.lib) isString imap0;
      inherit (inputs.jobInputs)
        jobKey
        requiredSystemFeatures
        ;
    in
    options
    // {
      name = if (options ? name && options.name != "") then options.name else jobKey;
      needs =
        if options ? needs then
          if isString options.needs then [ options.needs ] else options.needs
        else
          null;
      buildSystem = pkgs.stdenv.buildPlatform.system;
      hostSystem = pkgs.stdenv.hostPlatform.system;
      inherit requiredSystemFeatures;
      steps = filter (step: step != null) (
        imap0 (
          i: step:
          stepFn {
            inherit
              pkgs
              step
              ;
            placeholderName = "${jobKey}-${toString i}";
            jobEnv = options.env or { };
            jobSandbox = options.sandbox or { };
            jobPathLockdown = options.pathLockdown or false;
          }
        ) options.steps
      );
    }
  );

  meta.description = ''
    A job is a set of tasks built and run on a single local or remote runner,
    made from any number of sequential steps.

    When defined via `runner.matrix`, you can specify several versions of the same job,
    which may run concurrently on multiple builders and runners.
  '';
}
