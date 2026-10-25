#! /usr/bin/env nix
#! nix shell . --command now
{ runner, ... }:
let
  inputs = import ./.tack;
  pkgs = import inputs.nixpkgs { };
  now = import ./. { inherit pkgs; };

  tests = import ./.now/tests.nix { inherit now pkgs; };

  mkOptionDocumentation =
    level: module:
    { name, value }:
    let
      inherit (pkgs.lib) generators;
      inherit (pkgs.lib.strings) replicate;
    in
    ''
      ${replicate level "#"} ${module}.${name}

      ${value.description or ""}

      ${if value ? type then "_Type:_ `${value.type.name}`" else ""}

      ${
        if value ? default then
          ''
            _Default:_

            ```nix
            ${generators.toPretty {
              multiline = true;
              allowPrettyValues = true;
            } value.default}
            ```
          ''
        else
          ""
      }
    '';

  mkModuleDocumentation =
    level:
    { name, value }:
    let
      inherit (builtins) concatStringsSep;
      inherit (pkgs.lib) attrsToList;
      inherit (pkgs.lib.strings) replicate;
    in
    ''
      ${replicate level "#"} ${name}

      ${value.meta.description or ""}

      Available options:

      ${concatStringsSep "\n\n" (
        map (mkOptionDocumentation (level + 1) name) (
          builtins.filter ({ value, ... }: value ? description) (attrsToList value.options)
        )
      )}
    '';

  mkDocumentation =
    level: modules:
    let
      inherit (builtins) concatStringsSep;
      inherit (pkgs.lib) attrsToList;
    in
    concatStringsSep "\n\n" (
      map (mkModuleDocumentation level) (
        builtins.filter ({ value, ... }: value.meta.generateDocs or true) (attrsToList modules)
      )
    );
in
pkgs.lib.recursiveUpdate tests {
  jobs = {

    # ============================================================
    #                              Docs
    # ============================================================

    serve-docs = {
      name = "Serve docs";
      steps = [
        {
          path = [
            now
            pkgs.watchexec
            pkgs.zensical
          ];
          run = ''
            trap 'kill 0' EXIT INT TERM
            watchexec -w now.nix -w now/modules -r now run generate-nix-docs --logging step &
            watchexec -w now.nix -w src -r now run generate-cli-docs --logging step &
            watchexec -w now.nix -w .tack/pins.lock.json -r now run generate-now-services-docs --logging step &
            zensical serve -f docs/zensical.toml
          '';
        }
      ];
    };

    publish-docs = {
      name = "Build and publish docs";
      needs = [
        "generate-nix-docs"
        "generate-cli-docs"
        "generate-now-services-docs"
      ];
      sandbox.enable = true;
      steps = [
        {
          sandbox.writableDirectory = true;
          path = [ pkgs.zensical ];
          run = "zensical build -f docs/zensical.toml";
        }
        {
          sandbox = {
            useHome = [ ".ssh" ];
            networkAccess = true;
          };
          env.DOCS_HOST = runner.secret "DOCS_HOST";
          path = [
            pkgs.openssh
            pkgs.rsync
          ];
          run = ''
            rsync --delete-after -acP docs/site/ $DOCS_HOST:''${DOCS_DIRECTORY:-www}
          '';
        }
      ];
    };

    generate-nix-docs = {
      name = "Generate Nix docs";
      sandbox.enable = true;
      steps =
        let
          adios = (import inputs.adios) // {
            evalId = "";
            evalModule = _: { };
            envType =
              let
                inherit (adios) types;
              in
              types.union [
                types.string
                (types.struct "nowSecret" { })
                (types.struct "nowDownload" { })
              ];
          };
        in
        [
          (runner.steps.upload {
            name = "docs-workflow";
            deriv = pkgs.writeText "docs-workflow" (
              mkDocumentation 2 {
                workflow = import ./now/modules/workflow.nix adios;
              }
            );
          })
          (runner.steps.upload {
            name = "docs-job";
            deriv = pkgs.writeText "docs-job" (
              mkDocumentation 2 {
                job = import ./now/modules/job.nix adios;
              }
            );
          })
          (runner.steps.upload {
            name = "docs-step";
            deriv = pkgs.writeText "docs-step" (
              mkDocumentation 2 {
                step = import ./now/modules/step.nix adios;
              }
            );
          })
          (runner.steps.upload {
            name = "docs-sandbox";
            deriv = pkgs.writeText "docs-sandbox" (
              mkDocumentation 2 {
                sandbox = import ./now/modules/sandbox.nix adios;
              }
            );
          })
          {
            sandbox.writableDirectory = true;
            env = {
              DOCS_WORKFLOW = runner.download "docs-workflow";
              DOCS_JOB = runner.download "docs-job";
              DOCS_STEP = runner.download "docs-step";
              DOCS_SANDBOX = runner.download "docs-sandbox";
              OUT = "docs/docs/options.md";
            };
            run = ''
              set -euo pipefail

              cat > $OUT << EOF
              ---
              icon: lucide/square-menu
              ---

              # Options reference

              !!! note

                  This documentation is auto-generated from the workflow definitions.

              $(cat $DOCS_WORKFLOW)

              $(cat $DOCS_JOB)

              $(cat $DOCS_STEP)

              $(cat $DOCS_SANDBOX)
              EOF

              echo "Updated Nix docs."
            '';
          }
        ];
    };

    generate-cli-docs = {
      name = "Generate CLI docs";
      sandbox.enable = true;
      steps = [
        (runner.steps.upload {
          name = "docs-cli";
          deriv =
            pkgs.runCommand "now-cli"
              {
                nativeBuildInputs = [
                  now
                  pkgs.to-html
                ];
              }
              ''
                mkdir $out
                to-html --no-prompt "now help" > $out/index.html
                to-html --no-prompt "now help init" > $out/init.html
                to-html --no-prompt "now help list" > $out/list.html
                to-html --no-prompt "now help eval" > $out/eval.html
                to-html --no-prompt "now help run" > $out/run.html
              '';
        })
        {
          sandbox.writableDirectory = true;
          env = {
            DOCS_CLI = runner.download "docs-cli";
            OUT = "docs/docs/cli.md";
          };
          run = ''
            set -euo pipefail

            cat > $OUT << EOF
            ---
            icon: lucide/terminal
            ---

            # CLI reference

            !!! note

                This documentation is auto-generated from the command line.

            ## now

            $(cat $DOCS_CLI/index.html)

            ## now init

            $(cat $DOCS_CLI/init.html)

            ## now list

            $(cat $DOCS_CLI/list.html)

            ## now eval

            $(cat $DOCS_CLI/eval.html)

            ## now run

            $(cat $DOCS_CLI/run.html)
            EOF

            echo "Updated CLI docs."
          '';
        }
      ];
    };

    generate-now-services-docs = {
      name = "Generate now-services docs";
      sandbox.enable = true;
      steps = [
        (runner.steps.upload {
          name = "docs-now-services";
          deriv =
            let
              adios = import inputs.adios;
              services = adios.lib.importModules { directory = "${inputs.now-services}/services"; };
            in
            pkgs.writeText "docs-now-services" (mkDocumentation 3 services);
        })
        {
          sandbox.writableDirectory = true;
          env = {
            DOCS_NOW_SERVICES = runner.download "docs-now-services";
            OUT = "docs/docs/services.md";
          };
          run = ''
            set -euo pipefail

            cat > $OUT << EOF
            ---
            icon: lucide/circle-pile
            ---

            # now-services

            [\`now-services\`](https://codeberg.org/now-runner/now-services) is a pluggable collection of steps that let you run development services with \`now\`.

            ## Installation

            === "tack"

                \`\`\`bash
                tack add now-services git+https://codeberg.org/now-runner/now-services.git --fetch
                \`\`\`

                \`\`\`nix title="now.nix"
                let
                  inputs = import ./.tack;
                  services = import inputs.now-services;
                in
                {
                  jobs.my_job.steps = [
                    (services.postgresql { })
                  ];
                }
                \`\`\`

            === "npins"

                \`\`\`bash
                npins add git https://codeberg.org/now-runner/now-services.git
                \`\`\`

                \`\`\`nix title="now.nix"
                let
                  sources = import ./npins;
                  services = import sources.now-services;
                in
                {
                  jobs.my_job.steps = [
                    (services.postgresql { })
                  ];
                }
                \`\`\`

            === "Nix flake"

                \`\`\`nix title="flake.nix"
                {
                  inputs = {
                    # ...
                    now-services.url = "git+https://codeberg.org/now-runner/now-services.git";
                  };

                  outputs =
                    {
                      now-services,
                      ...
                    }@inputs:
                    {
                      now.jobs.my_job.steps = [
                        (now-services.postgresql { })
                      ];
                    };
                }
                \`\`\`

            ## Available services

            !!! note

                This documentation is auto-generated from the service definitions.

            $(cat $DOCS_NOW_SERVICES)
            EOF

            echo "Updated now-services docs."
          '';
        }
      ];
    };

    # ============================================================
    #                             Tests
    # ============================================================

    test = {
      name = "Finalize tests";
      needs = builtins.attrNames tests.jobs;
      steps = [
        {
          shell = pkgs.nushell;
          run = ''
            'Good to go! ^u^' | ansi gradient -F rainbow
          '';
        }
      ];
    };
  };
}
