{ types, ... }:
{
  options = {
    name = {
      type = types.nullOr types.string;
      default = null;
      description = "Name of the step.";
    };
    shell = {
      type = types.derivation;
      defaultFunc = { inputs }: inputs.nixpkgs.pkgs.bash;
      description = "The shell to use for this step.";
    };
    shellArgs = {
      type = types.nullOr (types.listOf types.string);
      default = null;
      description = "Args passed to the shell used in this step.";
    };
    run = {
      type = types.string;
      default = "";
      description = "Shell script to run on this step.";
    };
    path = {
      type = types.listOf types.derivation;
      default = [ ];
      description = "Packages added to the PATH of the script.";
    };
    env = {
      type = types.attrsOf (
        types.union [
          types.string
          (types.struct "cixSecret" { __cixSecret = types.string; })
        ]
      );
      default = { };
      description = "Environment values to make available to the script.";
    };
  };

  inputs = {
    nixpkgs.from = { parent }: parent.nixpkgs;
    cix.from = { parent }: parent.cix;
  };

  impl =
    { options, inputs }:
    let
      inherit (inputs.nixpkgs.pkgs)
        lib
        writeShellApplication
        writeTextFile
        ;
      inherit (inputs.cix) cix;
      script = writeTextFile {
        name = "cix-step-script";
        text = ''
          #! ${lib.getExe options.shell} ${
            lib.optionalString (options.shellArgs != null) (lib.escapeShellArgs options.shellArgs)
          }
          ${options.run}
        '';
        executable = true;
      };
    in
    writeShellApplication {
      name = "cix-step";
      runtimeInputs = options.path ++ [ cix ];
      text = ''
        cix step ${script} ${
          lib.optionalString (options.name != null) "--name ${lib.strings.escapeShellArg options.name}"
        }
      '';
    };
}
