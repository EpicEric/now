#! /usr/bin/env nix
#! nix shell . --command now
{ runner, ... }:
let
  inputs = import ./.tack;
  pkgs = import inputs.nixpkgs { };
  now = import ./. { inherit pkgs; };

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
{
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
      needs = [
        "test-abort"
        "test-checkout"
        "test-checkout-remote"
        "test-conditionals"
        "test-cycle"
        "test-dotenv"
        "test-dry-run"
        "test-env"
        "test-error"
        "test-fail-fast"
        "test-fhs"
        "test-flake"
        "test-flake-attr"
        "test-gcroot-dir"
        "test-glob"
        "test-graceful-termination"
        "test-init"
        "test-invalid-env"
        "test-invalid-output-var"
        "test-job-timeout"
        "test-jobs"
        "test-list"
        "test-local-only"
        "test-matrix"
        "test-missing-download"
        "test-missing-secret"
        "test-missing-var"
        "test-nix-config"
        "test-nixpkgs"
        "test-no-default-jobs"
        "test-no-jobs"
        "test-no-match"
        "test-orchestrate-services"
        "test-overlay"
        "test-path-lockdown"
        "test-sandbox"
        "test-script"
        "test-secret-redaction"
        "test-secret-reuse"
        "test-shell-args"
        "test-skip"
        "test-tempdir"
        "test-unknown-needs"
        "test-upload"
        "test-var-script"
        "test-vars"
        "test-workflow-timeout"
      ];
      steps = [
        {
          shell = pkgs.nushell;
          run = ''
            'Good to go! ^u^' | ansi gradient -F rainbow
          '';
        }
      ];
    };

    test-abort = {
      name = "Test --abort";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --abort --workflow .now/tests/abort.nix --all-jobs | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            for i in 0..5 {
              if not ($output | str contains $"=> ($i)") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected '=> ($i)' in output"
                exit 1
              }
            }

            if ($output | str contains "late ran") {
              print $"(ansi red_bold)ERROR:(ansi reset) 'late' job should have been aborted"
              exit 1
            }

            if not ($output | str contains "=== note: teardown still runs on error ===") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected teardown note in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-checkout = {
      name = "Test local checkout";
      steps = [
        {
          path = [
            pkgs.git
            now
          ];
          shell = pkgs.nushell;
          run = ''
            let tempdir = (mktemp -p ($env.TMPDIR? | default "/tmp") -d)
            git init -b main $tempdir
            'Foo contents' | save ($tempdir | path join foo)
            'Bar contents' | save ($tempdir | path join bar)
            'bar' | save ($tempdir | path join .gitignore)

            now run --cwdir $tempdir --all-jobs --workflow .now/tests/checkout.nix
            rm -rf $tempdir
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-checkout-remote = {
      name = "Test remote checkout";
      steps = [
        {
          path = [
            pkgs.git
            now
          ];
          shell = pkgs.nushell;
          run = ''
            if BUILDERS in $env {
              let tempdir = (mktemp -p ($env.TMPDIR? | default "/tmp") -d)
              git init -b main $tempdir
              'Foo contents' | save ($tempdir | path join foo)
              'Bar contents' | save ($tempdir | path join bar)
              'bar' | save ($tempdir | path join .gitignore)

              now run --cwdir $tempdir --builders $env.BUILDERS --all-jobs --workflow .now/tests/checkout.nix
              rm -rf $tempdir
              if $env.LAST_EXIT_CODE != 0 {
                print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
                exit 1
              }

              print $"(ansi green)Test passed.(ansi reset)"
            } else {
              print $"(ansi yellow_bold)WARNING:(ansi reset) BUILDERS is unset; skipping"
              print ""
              print $"(ansi d)=== hint: to run this, pass an envvar like:(ansi reset)"
              print $"(ansi d)===   BUILDERS='ssh://localhost - - 1 1 now now -'(ansi reset)"
            }
          '';
        }
      ];
    };

    test-conditionals = {
      name = "Test conditionals";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --all-jobs --workflow .now/tests/conditionals.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-cycle = {
      name = "Test cycle";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --abort --workflow .now/tests/cycle.nix --all-jobs | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Cycle detected") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected a 'Cycle detected' error"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-dotenv = {
      name = "Test --env-file";
      steps = [
        {
          path = [
            pkgs.git
            now
          ];
          shell = pkgs.nushell;
          run = ''
            let tmp = mktemp
            r#'MY_VAR="This is a variable"
            MY_SECRET='This is a secret'
            '# | save --force $tmp

            now run --env-file $tmp --workflow .now/tests/env.nix
            rm $tmp
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-dry-run = {
      name = "Test --dry-run";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            # Error job should pass.
            now run --dry-run --workflow .now/tests/error.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            # Malformed job (eg. cyclic graph) should fail.
            let result = (now run --dry-run --workflow .now/tests/cycle.nix --all-jobs | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Cycle detected") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected a 'Cycle detected' error"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-env = {
      name = "Test environment";
      steps = [
        {
          env = {
            MY_VAR = "This is a variable";
            MY_SECRET = "This is a secret";
          };
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/env.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-error = {
      name = "Test error exit status";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            # Ensure the test evaluates just fine
            now eval --workflow .now/tests/error.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed to evaluate"
              exit 1
            }

            let result = (now run --workflow .now/tests/error.nix --all-jobs | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "=== note: teardown still runs on error ===") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected teardown note in output"
              exit 1
            }

            if ($output | str contains "This shouldn't be printed at all!") {
              print $"(ansi red_bold)ERROR:(ansi reset) Steps after a failed step should not run"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-fail-fast = {
      name = "Test strategy.failFast";
      steps = [
        {
          name = "failFast = true";
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            if BUILDERS in $env {
              let result = (now run --workflow .now/tests/fail-fast/true.nix --builders $env.BUILDERS | complete)
              let output = $result.stdout + $result.stderr
              print $output

              if $result.exit_code == 0 {
                print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
                exit 1
              }

              if not ($output | str contains "Doing local work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected local run in output"
                exit 1
              }
              if not ($output | str contains "Doing remote work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected remote run in output"
                exit 1
              }
              if ($output | str contains "Done with remote work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Remote run should've been aborted"
                exit 1
              }

              if not ($output | str contains "Local teardown") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected local teardown in output"
                exit 1
              }
              if not ($output | str contains "Remote teardown") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected remote teardown in output"
                exit 1
              }

              if not ($output | str contains "Job 'job-remote' was aborted") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected abort message in output"
                exit 1
              }

              print $"(ansi green)Test passed.(ansi reset)"
            } else {
              print $"(ansi yellow_bold)WARNING:(ansi reset) BUILDERS is unset; skipping"
              print ""
              print $"(ansi d)=== hint: to run this, pass an envvar like:(ansi reset)"
              print $"(ansi d)===   BUILDERS='ssh://localhost - - 1 1 now now -'(ansi reset)"
            }
          '';
        }
        {
          name = "failFast = false";
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            if BUILDERS in $env {
              let result = (now run --workflow .now/tests/fail-fast/false.nix --builders $env.BUILDERS | complete)
              let output = $result.stdout + $result.stderr
              print $output

              if $result.exit_code == 0 {
                print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
                exit 1
              }

              if not ($output | str contains "Doing local work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected local run in output"
                exit 1
              }
              if not ($output | str contains "Doing remote work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected remote run in output"
                exit 1
              }
              if not ($output | str contains "Done with remote work") {
                print $"(ansi red_bold)ERROR:(ansi reset) Remote run shouldn't have been aborted"
                exit 1
              }

              if not ($output | str contains "Local teardown") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected local teardown in output"
                exit 1
              }
              if not ($output | str contains "Remote teardown") {
                print $"(ansi red_bold)ERROR:(ansi reset) Expected remote teardown in output"
                exit 1
              }

              if ($output | str contains "Job 'job-remote' was aborted") {
                print $"(ansi red_bold)ERROR:(ansi reset) Unexpected abort message in output"
                exit 1
              }

              print $"(ansi green)Test passed.(ansi reset)"
            } else {
              print $"(ansi yellow_bold)WARNING:(ansi reset) BUILDERS is unset; skipping"
              print ""
              print $"(ansi d)=== hint: to run this, pass an envvar like:(ansi reset)"
              print $"(ansi d)===   BUILDERS='ssh://localhost - - 1 1 now now -'(ansi reset)"
            }
          '';
        }
      ];
    };

    test-fhs = {
      name = "Test FHS environment";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/fhs.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-flake = {
      name = "Test flake";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --flake .now/tests flake
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            now run --flake .now/tests#other-entrypoint example
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-flake-attr = {
      name = "Test flake attribute parsing";
      steps = [
        {
          name = "test-flake-attr-valid";
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --flake '.now/tests#"quoted entrypoint"' quoted | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Quoted attribute failed"
              exit 1
            }

            if not ($output | str contains "quoted entrypoint ran") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected job output in result"
              exit 1
            }

            let result = (now run --flake '.now/tests#nested."sub attr"' nested | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Nested quoted attribute failed"
              exit 1
            }

            if not ($output | str contains "nested ran") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected job output in result"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
        {
          name = "test-flake-attr-invalid";
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            for attr in [ '"unclosed' 'bad!attr' 'a..b' '"a\qb"' ] {
              let result = (now run --flake ".now/tests#($attr)" | complete)
              let output = $result.stdout + $result.stderr
              print $output

              if $result.exit_code == 0 {
                print $"(ansi red_bold)ERROR:(ansi reset) Attribute '($attr)' should have been rejected"
                exit 1
              }
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-gcroot-dir = {
      name = "Test --gcroot-dir";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let gcrootdir = (mktemp -p ($env.TMPDIR? | default "/tmp") -d)
            now run --gcroot-dir $gcrootdir -w .now/tests/gcroot-dir.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              rm -rf $gcrootdir
              exit 1
            }

            let files = (ls -a $gcrootdir)
            print $files
            rm -rf $gcrootdir

            if ($files | where name =~ '-example-build\.drv$' | is-empty) {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing build in gcroot directory"
              exit 1
            }

            if ($files | where name =~ '-example-upload\.drv$' | is-empty) {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing upload in gcroot directory"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-glob = {
      name = "Test job globbing";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            for pattern in ["a/1*" "b/**/*" "c/f?o"] {
              now run $pattern --cores 1 --workflow .now/tests/glob.nix
              if $env.LAST_EXIT_CODE != 0 {
                print $"ERROR: now run failed for pattern '($pattern)'"
                exit 1
              }
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-graceful-termination = {
      name = "Test graceful termination";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let dir = (mktemp --directory)
            let log = ($dir | path join "output.log")

            let driver = r#'
              now run --workflow .now/tests/graceful-termination.nix > "$1" 2>&1 &
              pid=$!

              # Wait for the step to be running
              tries=0
              until grep -q "step: started" "$1" 2>/dev/null; do
                tries=$((tries + 1))
                if [ "$tries" -gt 1800 ]; then
                  kill -KILL "$pid" 2>/dev/null
                  exit 124
                fi
                sleep 0.1
              done

              kill -INT "$pid"

              # Watchdog: fail instead of freezing if now hangs after SIGINT
              ( sleep 10; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
              watchdog=$!
              wait "$pid"
              status=$?
              kill "$watchdog" 2>/dev/null
              exit "$status"
            '#

            let result = (^sh -c $driver sh $log | complete)
            let output = (open $log --raw)
            rm -rf $dir
            print $output

            if $result.exit_code == 124 {
              print $"(ansi red_bold)ERROR:(ansi reset) Step never started"
              exit 1
            }

            if $result.exit_code == 137 {
              print $"(ansi red_bold)ERROR:(ansi reset) now did not exit after SIGINT (killed by watchdog)"
              exit 1
            }

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Aborted workflow shouldn't have succeeded!"
              exit 1
            }

            if ($output | str contains "Done.") {
              print $"(ansi red_bold)ERROR:(ansi reset) Aborted workflow reported 'Done.'"
              exit 1
            }

            if ($output | str contains "teardown: marker=missing") {
              print $"(ansi red_bold)ERROR:(ansi reset) Step never ran its SIGTERM handler"
              exit 1
            }

            if ($output | str contains "teardown: marker=cleaning") {
              print $"(ansi red_bold)ERROR:(ansi reset) Teardown started while the step was still cleaning up"
              exit 1
            }

            if not ($output | str contains "teardown: marker=finished") {
              print $"(ansi red_bold)ERROR:(ansi reset) Teardown did not run after abort"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-init = {
      name = "Test `now init`";
      checkout = "none";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now init
            let result = (./now.nix run | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            if not ($output | str contains "Hello from now!") {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing default message in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-invalid-env = {
      name = "Test POSIX env validation";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now eval -w .now/tests/invalid-env.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded"
              exit 1
            }

            if not ($output | str contains "environment variable '🫪' does not have a valid POSIX variable name") {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-invalid-output-var = {
      name = "Test POSIX step.outputVar validation";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now eval -w .now/tests/invalid-output-var.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded"
              exit 1
            }

            if not ($output | str contains "output environment variable '🫪' is not a valid POSIX variable name") {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-job-timeout = {
      name = "Test job timeout";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/job-timeout.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Done!") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected the first step to complete before the timeout"
              exit 1
            }

            if not ($output | str contains "=== note: teardown still runs on timeout ===") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected teardown note in output"
              exit 1
            }

            if not ($output | str contains "timed out after 3s") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected a timeout error"
              exit 1
            }

            if ($output | str contains "This shouldn't be printed at all!") {
              print $"(ansi red_bold)ERROR:(ansi reset) The step that timed out should not have completed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-jobs = {
      name = "Test job dependencies";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run b x --workflow .now/tests/jobs.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-list = {
      name = "Test `now list`";
      steps = [
        {
          path = [
            now
            pkgs.graphviz
          ];
          shell = pkgs.nushell;
          run = ''
            let job_list = now list --workflow .now/tests/jobs.nix | split words
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) `now list` failed"
              exit 1
            }

            if $job_list != [a b c x y] {
              print $"(ansi red_bold)ERROR:(ansi reset) Invalid job list"
              exit 1
            }

            now list --tree --workflow .now/tests/jobs.nix | dot -Tplain-ext
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) `now list --tree` failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-local-only = {
      name = "Test --local-only";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          env.NIX_CONFIG = ''
            builders = ssh://localhost - - 1 1 now now -
          '';
          run = ''
            let result = (now run --local-only --workflow .now/tests/local-only.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "No runners match for job 'remote-job'") {
              print $"(ansi red_bold)ERROR:(ansi reset) Error didn't match"
              exit 1
            }

            if ($output | str contains "This shouldn't run") {
              print $"(ansi red_bold)ERROR:(ansi reset) Remote step shouldn't run"
              exit 1
            }

            if ($output | str contains "Teardown shouldn't run") {
              print $"(ansi red_bold)ERROR:(ansi reset) Remote teardown shouldn't run"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-matrix = {
      name = "Test run matrix";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          env.VAR_TO_PASS_TO_RUNNERS = "forty-two";
          run = ''
            if BUILDERS in $env {
              now run --all-jobs --builders $env.BUILDERS --workflow .now/tests/matrix.nix
              if $env.LAST_EXIT_CODE != 0 {
                print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
                exit 1
              }

              print $"(ansi green)Test passed.(ansi reset)"

            } else {
              print $"(ansi yellow_bold)WARNING:(ansi reset) BUILDERS is unset; skipping"
              print ""
              print $"(ansi d)=== hint: to run this, pass an envvar like:(ansi reset)"
              print $"(ansi d)===   BUILDERS='ssh://localhost - - 1 1 now now -'(ansi reset)"
            }
          '';
        }
      ];
    };

    test-missing-download = {
      name = "Test missing `runner.download`";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/missing-download.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "No upload named 'NO_DOWNLOAD'") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected missing download error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-missing-secret = {
      name = "Test missing `runner.secret`";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/missing-secret.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Secret environment variable 'NO_SECRET' is unset") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected missing secret error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-missing-var = {
      name = "Test missing `runner.var`";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/missing-var.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Required environment variable 'NO_VAR' is unset") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected missing var error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-nix-config = {
      name = "Test special steps' nixConfig";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/nix-config.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-nixpkgs = {
      name = "Test nixpkgs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/nixpkgs.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-no-default-jobs = {
      name = "Test missing default jobs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            # Selecting a job explicitly should still work
            now run a --workflow .now/tests/no-default.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Explicit job selection failed"
              exit 1
            }

            # Without a job argument, the missing default should be reported
            let result = (now run --workflow .now/tests/no-default.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "No default jobs in workflow") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected missing default error in output"
              exit 1
            }

            if not ($output | str contains "Available options: a") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected available jobs in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-no-jobs = {
      name = "Test workflow without jobs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/no-jobs.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "No jobs in workflow") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected empty workflow error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-no-match = {
      name = "Test no matching job";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/jobs.nix inexistent | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "No jobs matched 'inexistent'") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected match error in output"
              exit 1
            }

            if not ($output | str contains "Available options: a, b, c, x, y") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected suggestions in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-orchestrate-services = {
      name = "Test `now-services.orchestrate`";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let dir = (mktemp --directory)
            let log = ($dir | path join "output.log")

            let driver = r#'
              cd .now/tests/orchestrate-services
              now run > "$1" 2>&1 &
              pid=$!

              # Wait for the step to be running
              tries=0
              until grep -q "Started main()" "$1" 2>/dev/null; do
                tries=$((tries + 1))
                if [ "$tries" -gt 1800 ]; then
                  kill -KILL "$pid" 2>/dev/null
                  exit 124
                fi
                sleep 0.1
              done

              kill -INT "$pid"

              # Watchdog: fail instead of freezing if now hangs after SIGINT
              ( sleep 10; kill -KILL "$pid" 2>/dev/null ) >/dev/null 2>&1 &
              watchdog=$!
              wait "$pid"
              status=$?
              kill "$watchdog" 2>/dev/null
              exit "$status"
            '#

            let result = (^sh -c $driver sh $log | complete)
            let output = (open $log --raw)
            rm -rf $dir
            print $output

            if $result.exit_code == 124 {
              print $"(ansi red_bold)ERROR:(ansi reset) Step never started"
              exit 1
            }

            if $result.exit_code == 137 {
              print $"(ansi red_bold)ERROR:(ansi reset) now did not exit after SIGINT (killed by watchdog)"
              exit 1
            }

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Aborted workflow shouldn't have succeeded!"
              exit 1
            }

            if ($output | str contains "Finished main()") {
              print $"(ansi red_bold)ERROR:(ansi reset) Aborted workflow reported 'Finished main()'"
              exit 1
            }

            if not ($output | str contains "Caught signal: SIGTERM") {
              print $"(ansi red_bold)ERROR:(ansi reset) Step never ran its SIGTERM handler"
              exit 1
            }

            if not ($output | str contains "SystemExit: 42") {
              print $"(ansi red_bold)ERROR:(ansi reset) Step didn't exit with custom status code"
              exit 1
            }

            if not ($output | str contains "Runner aborted") {
              print $"(ansi red_bold)ERROR:(ansi reset) Runner didn't abort"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-overlay = {
      name = "Test overlay";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/overlay.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-path-lockdown = {
      name = "Test path lockdown";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/path-lockdown.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-sandbox = {
      name = "Test sandboxing";
      steps = [
        {
          path = [
            pkgs.git
            now
          ];
          shell = pkgs.nushell;
          run = ''
            let cwdir = (mktemp -p ($env.TMPDIR? | default "/tmp") -d)
            git init -b main $cwdir
            mkdir ($cwdir | path join bar)
            'Foo contents' | save ($cwdir | path join foo)
            'Baz contents' | save ($cwdir | path join bar/baz)

            now run --cwdir $cwdir --all-jobs --workflow .now/tests/sandbox.nix
            rm -rf $cwdir
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-script = {
      name = "Test script import";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/script.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-secret-redaction = {
      name = "Test secret redaction";
      steps = [
        {
          env.MY_SECRET = "redacted-secret-value";
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/secret-redaction.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            if ($output | str contains "redacted-secret-value") {
              print $"(ansi red_bold)ERROR:(ansi reset) Secret leaked into output"
              exit 1
            }

            if not ($output | str contains "plain: ***") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected redacted secret in output"
              exit 1
            }

            if not ($output | str contains "embedded: prefix-***-suffix") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected embedded secret to be redacted"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-secret-reuse = {
      name = "Test invalid secret reuse";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          env.SHARED_VAR = "supersecretpassword";
          run = ''
            let result = (now eval -w .now/tests/secret-reuse.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded"
              exit 1
            }

            if not ($output | str contains "secret 'SHARED_VAR' cannot also be used as a regular variable") {
              print $"(ansi red_bold)ERROR:(ansi reset) Missing error in output"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-shell-args = {
      name = "Test step.shellArgs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/shell-args.nix shellArgs | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test should have succeeded!"
              exit 1
            }

            if not ($output | str contains "* * *") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected non-globbed string"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-skip = {
      name = "Test skip non-runnable jobs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --builders "" --skip --all-jobs --workflow .now/tests/skip.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-tempdir = {
      name = "Test runner.steps.tempdir";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/tempdir.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-unknown-needs = {
      name = "Test unknown needs";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/unknown-needs.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Unknown node does-not-exist") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected unknown node error in output"
              exit 1
            }

            if ($output | str contains "This shouldn't run") {
              print $"(ansi red_bold)ERROR:(ansi reset) Step should not have run"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-upload = {
      name = "Test uploads";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/upload.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-var-script = {
      name = "Test runner.var disallowed in scripts";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/var-script.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "cannot be used directly in") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected a 'cannot be used directly in' error"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-vars = {
      name = "Test envvars";
      steps = [
        {
          env = {
            TEST_FIRST_VAR = "first var";
            TEST_FIRST_SECRET = "first secret";
            TEST_SECOND_VAR = "second var";
            TEST_SECOND_SECRET = "second secret";
          };
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --workflow .now/tests/vars.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };

    test-workflow-timeout = {
      name = "Test workflow timeout";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            # Ensure workflow is cached
            now run --workflow .now/tests/workflow-timeout.nix
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
              exit 1
            }

            let result = (now run --timeout 3s --workflow .now/tests/workflow-timeout.nix | complete)
            let output = $result.stdout + $result.stderr
            print $output

            if $result.exit_code == 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test shouldn't have succeeded!"
              exit 1
            }

            if not ($output | str contains "Done!") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected the first step to complete before the timeout"
              exit 1
            }

            if not ($output | str contains "=== note: teardown still runs on timeout ===") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected teardown note in output"
              exit 1
            }

            if not ($output | str contains "timed out after 3s") {
              print $"(ansi red_bold)ERROR:(ansi reset) Expected a timeout error"
              exit 1
            }

            if ($output | str contains "This shouldn't be printed at all!") {
              print $"(ansi red_bold)ERROR:(ansi reset) The step that timed out should not have completed"
              exit 1
            }

            print $"(ansi green)Test passed.(ansi reset)"
          '';
        }
      ];
    };
  };
}
