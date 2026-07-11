{ types, ... }:
{
  options = {
    name = {
      type = types.nullOr types.string;
      default = null;
      description = "Name of the job.";
    };
    runs-on = {
      type = types.string;
      defaultFunc = { inputs }: inputs.nixpkgs.pkgs.stdenv.hostPlatform;
      description = "Which kind of runner supports this job.";
    };
    needs = {
      type = types.nullOr (types.listOf types.string);
      default = null;
      description = "Jobs that must be completed before running this one.";
    };
    steps = {
      type = types.listOf (
        types.union [
          types.null
          step
        ]
      );
      default = [ ];
      description = "Steps to run in this job.";
    };
  };

  inputs = {
    nixpkgs.from = { parent }: parent.nixpkgs;
  };
}
