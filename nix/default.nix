{
  system ? builtins.currentSystem,
  inputs ? import ../.tack,
  pkgs ? import inputs.nixpkgs {
    inherit system;
    overlays = [ (import inputs.rust-overlay) ];
  },
  craneLib ? (import inputs.crane { inherit pkgs; }).overrideToolchain (
    p: p.rust-bin.stable.latest.default
  ),
}:
let
  inherit (pkgs) lib;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      (craneLib.fileset.commonCargoSources ../.)
    ];
  };

  commonArgs = {
    inherit src;
    strictDeps = true;

    nativeBuildInputs = [ ];
  };

  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

  cix = craneLib.buildPackage (
    commonArgs
    // {
      inherit cargoArtifacts;
      doCheck = false;
      # postInstall = lib.optionalString (pkgs.stdenv.buildPlatform.canExecute pkgs.stdenv.hostPlatform) ''
      #   installShellCompletion --cmd cix \
      #     --bash <($out/bin/cix completions bash) \
      #     --fish <($out/bin/cix completions fish) \
      #     --zsh <($out/bin/cix completions zsh)
      # '';
      meta = {
        name = "cix";
        description = "TO-DO";
        homepage = "TO-DO";
        license = lib.licenses.mit;
        mainProgram = "cix";
        platforms = lib.platforms.linux ++ lib.platforms.darwin;
      };
    }
  );
in
{
  inherit cix;

  shell = craneLib.devShell {
    packages = [ ];
  };
}
