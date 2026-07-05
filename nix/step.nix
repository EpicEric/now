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
      type = types.attrsOf types.string;
      default = { };
      description = "Environment values to make available to the script.";
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };

  impl =
    {
      options,
      inputs,
    }:
    let
      inherit (inputs.nixpkgs) pkgs;
      inherit (pkgs) lib;
      cix = "TODO";
      script = pkgs.writeTextFile {
        name = "script";
        text = ''
          #! ${lib.getExe options.shell}
          ${options.run}
        '';
        executable = true;
      };
    in
    pkgs.stdenvNoCC.mkDerivation {
      name = "cix-step";
      dontUnpack = true;
      strictDeps = true;
      __structuredAttrs = true;
      nativeBuildInputs = [ pkgs.makeWrapper ];
      buildPhase = ''
        runHook preBuild
        mkdir -p $out/bin
        makeWrapper ${cix}/bin/cix $out/bin/cix-step \
          --add-flags 'step ${script} ${if inputs.name != null then "--name ${inputs.name}" else ""}' \
          --prefix PATH : ${lib.makeBinPath options.path}
        runHook postBuild
      '';
      meta.mainProgram = "cix-step";
    };
}
