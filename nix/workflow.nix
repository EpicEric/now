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
  cix ?
    (import ./. {
      inherit
        system
        inputs
        pkgs
        craneLib
        ;
    }).cix,
}:
let
  inherit (pkgs) lib;

  cixConfig =
    module:
    builtins.toJSON (
      module.config
      // {
        jobs = builtins.mapAttrs (
          _: job:
          job
          // {
            steps = map (
              step:
              let
                inherit (pkgs)
                  writeShellApplication
                  writeTextFile
                  ;
                script = writeTextFile {
                  name = "cix-step-script";
                  text = ''
                    #! ${lib.getExe step.shell} ${
                      lib.optionalString (step.shellArgs != null) (lib.escapeShellArgs step.shellArgs)
                    }
                    ${step.run}
                  '';
                  executable = true;
                };
              in
              writeShellApplication {
                name = "cix-step";
                runtimeInputs = step.path ++ [ cix ];
                text = ''
                  cix step ${script} ${
                    lib.optionalString (step.name != null) "--name ${lib.strings.escapeShellArg step.name}"
                  }
                '';
              }
            ) job.steps;
          }
        ) module.config.jobs;
      }
    );
in
workflow: env:
cixConfig (
  lib.evalModules {
    class = "cix";
    modules = [
      ./module.nix
      workflow
    ];
    specialArgs = {
      inherit pkgs;
      ci = {
        secrets = lib.genAttrs env.secrets (name: {
          __cixSecret = name;
        });
        matrix = variants: fn: map (v: fn v) variants;
        steps = {
          checkout =
            {
              name ? null,
              persist-credentials ? false,
            }:
            {
              inherit name;
              run = ''
                echo "TO-DO - persist-credentials = ${lib.boolToString persist-credentials}"
              '';
              path = [
                pkgs.git
              ];
            };
        };
      };
    };
  }
)
