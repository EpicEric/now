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

  mapMaybeList = fn: elem: if builtins.isList elem then map fn elem else fn elem;

  cixConfig =
    module:
    builtins.toJSON (
      module.config
      // {
        jobs = builtins.mapAttrs (
          _: job:
          mapMaybeList (
            job':
            job'
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
                  runtimeInputs = [ cix ] ++ step.path;
                  text = ''
                    cix step ${script} ${
                      lib.optionalString (step.name != null) "--name ${lib.strings.escapeShellArg step.name}"
                    }
                  '';
                }
              ) job'.steps;
            }
          ) job
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

        inherit (env) vars;

        matrix = variants: fn: map (v: fn v) variants;

        steps = {
          build =
            name: deriv:
            assert lib.assertMsg (lib.isStorePath deriv)
              "derivation argument to ci.steps.build must be a derivation";
            {
              name = "cix: Build ${if name == "" then deriv else name}";
              run = ''
                cix build ${deriv}
              '';
            };

          upload =
            name: deriv:
            assert lib.assertMsg (name != "") "name argument to ci.steps.upload must not be empty";
            assert lib.assertMsg (lib.isStorePath deriv)
              "derivation argument to ci.steps.upload must be a derivation";
            {
              name = "cix: Upload ${name}";
              run = ''
                cix upload ${lib.escapeShellArg name} --derivation ${deriv}
              '';
            };
        };
      };
    };
  }
)
