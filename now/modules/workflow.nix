{
  promise,
  types,
  evalModule,
  ...
}@adios:

let
  mapMaybeJobList =
    {
      job',
      jobKey,
      pkgs,
      overlay,
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
        normalizeJob {
          inherit
            job
            jobKey
            pkgs
            specialArgs
            requiredSystemFeatures
            ;
        };
    in
    if builtins.isList job' then
      map (
        element:
        normalize {
          inherit (element) job;
          pkgs = if element ? pkgs then element.pkgs.extend overlay else pkgs;
          specialArgs = element.specialArgs or { };
          requiredSystemFeatures = element.requiredSystemFeatures or [ ];
        }
      ) job'
    else
      normalize { job = job'; };

  normalizeJob =
    {
      job,
      jobKey,
      pkgs,
      requiredSystemFeatures,
      specialArgs,
    }:
    evalModule {
      inherit (pkgs) lib;
      module =
        ((import ./. adios) {
          options = {
            "/job/jobInputs" = {
              inherit jobKey requiredSystemFeatures;
            };
            "/job/nixpkgs" = {
              inherit pkgs;
            };
          };
        }).modules.job;
      specialArgs = specialArgs // {
        inherit pkgs;
      };
      args = job;
    };
in

{
  inputs = {
    nixpkgs.from = { self }: self.nixpkgs;
    workflowInputs.from = { self }: self.workflowInputs;
  };

  options = {
    name = {
      type = types.string;
      description = "Name of the workflow.";
    };
    default = {
      type = types.either types.string (types.listOf types.string);
      description = "Default job(s) to run for this workflow.";
    };
    nixpkgs = {
      type = types.any;
      description = "Nix expression that evaluates to nixpkgs. Defaults to `<nixpkgs>`.";
    };
    jobs = {
      type = types.attrsOf (
        types.nullOr (
          types.new {
            name = "job";
            verify = _: true;
          }
        )
      );
      description = ''
        Jobs in the workflow.
        See the [submodule documentation](#job).
      '';
    };
  };

  modules = {
    nixpkgs = import ./nixpkgs.nix adios;
    workflowInputs = import ./workflowInputs.nix adios;
  };

  result = promise (
    { inputs, options }:
    let
      inherit (builtins) isString mapAttrs;
      inherit (inputs.nixpkgs.pkgs.lib) filterAttrs;
    in
    options
    // {
      default =
        if options ? default then
          if isString options.default then [ options.default ] else options.default
        else
          null;
      jobs = filterAttrs (_: value: value != null) (
        mapAttrs (
          jobKey: job':
          mapMaybeJobList {
            inherit (inputs.nixpkgs) pkgs;
            inherit (inputs.workflowInputs) overlay;
            inherit job' jobKey;
          }
        ) options.jobs
      );
    }
  );

  meta.description = ''
    A workflow is the main definition of your `now` commands.
    It allows you to specify multiple scripts (jobs) in a single
    source of truth via Nix.
  '';
}
