{ runner, ... }:
let
  inputs = import ./.tack;
  pkgs = import inputs.nixpkgs { };
  now = import ./. { inherit pkgs; };
in
{
  jobs = {

    # ============================================================
    #                           Development
    # ============================================================

    format = {
      name = "Fix formatting";
      steps = [
        {
          run = ''
            cargo fmt --all
            treefmt
          '';
          path = [
            pkgs.cargo
            pkgs.rustfmt
            pkgs.nixfmt-tree
          ];
          sandbox = {
            enable = true;
            writableDirectory = true;
          };
        }
      ];
    };

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
            watchexec -w now.nix -w nix/types.nix -r now run generate-nix-docs &
            watchexec -w now.nix -w src -r now run generate-cli-docs &
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
      ];
      sandbox.enable = true;
      steps = [
        {
          sandbox.writableDirectory = true;
          path = [ pkgs.zensical ];
          run = "zensical build -f docs/zensical.toml";
        }
        {
          sandbox.networkAccess = true;
          env.DOCS_HOST = runner.secret "DOCS_HOST";
          path = [ pkgs.rsync ];
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
          evalOptions =
            type:
            pkgs.lib.evalModules {
              modules = [ type ];
              specialArgs = { inherit pkgs; };
            };

          moduleDocs =
            type:
            (pkgs.nixosOptionsDoc {
              options = removeAttrs (evalOptions type).options [ "_module" ];
            }).optionsCommonMark;

          types = import ./nix/types.nix { inherit (pkgs) lib; };
        in
        [
          (runner.steps.upload {
            name = "docs-workflow";
            deriv = moduleDocs types.workflow;
          })
          (runner.steps.upload {
            name = "docs-job";
            deriv = moduleDocs {
              options.job = pkgs.lib.mkOption {
                description = ''
                  A job is a set of tasks built and run on a single local or remote runner,
                  made from any number of sequential steps.

                  When defined via `runner.matrix`, you can specify several versions of the same job,
                  which may run concurrently on multiple builders and runners.
                '';
                type = types.job {
                  evalId = "";
                  inherit pkgs;
                };
              };
            };
          })
          (runner.steps.upload {
            name = "docs-step";
            deriv = moduleDocs {
              options.step = pkgs.lib.mkOption {
                description = ''
                  A step is a single, atomic task that's run as part of a job.
                '';
                type = types.step {
                  evalId = "";
                  inherit pkgs;
                };
              };
            };
          })
          (runner.steps.upload {
            name = "docs-sandbox";
            deriv = moduleDocs {
              options.sandbox = pkgs.lib.mkOption {
                description = ''
                  The sandbox submodule allows you to specify extra restrictions at
                  a job or step level.

                  Any step settings override job settings. For example, this allows you to configure
                  sandboxing for all steps in a job with `sandbox.enable = true;`, then loosen
                  permissions on individual steps that have to write to the filesystem.

                  On Linux, [`bubblewrap`](https://github.com/containers/bubblewrap) is used;
                  on macOS, `sandbox-exec` is used.
                '';
                type = types.sandbox;
              };
            };
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

              echo "---" > $OUT
              echo "icon: lucide/square-menu" >> $OUT
              echo "---" >> $OUT
              echo "# Options reference" >> $OUT
              echo "" >> $OUT
              echo "!!! note" >> $OUT
              echo "" >> $OUT
              echo "    This documentation is auto-generated from the workflow definitions." >> $OUT
              echo "" >> $OUT
              echo "## Workflow" >> $OUT
              echo "" >> $OUT
              echo "A workflow is the main definition of your now commands. \
              It allows you to specify multiple scripts (jobs) in a single source of truth via Nix." >> $OUT
              echo "" >> $OUT
              cat $DOCS_WORKFLOW | sed 's/## /### /g' >> $OUT
              echo "## Job" >> $OUT
              echo "" >> $OUT
              cat $DOCS_JOB | sed 's/## /### /g' >> $OUT
              echo "" >> $OUT
              echo "## Step" >> $OUT
              echo "" >> $OUT
              cat $DOCS_STEP | sed 's/## /### /g' >> $OUT
              echo "" >> $OUT
              echo "## Sandbox" >> $OUT
              echo "" >> $OUT
              cat $DOCS_SANDBOX | sed 's/## /### /g' >> $OUT

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

            echo "---" > $OUT
            echo "icon: lucide/terminal" >> $OUT
            echo "---" >> $OUT
            echo "# CLI reference" >> $OUT
            echo "" >> $OUT
            echo "!!! note" >> $OUT
            echo "" >> $OUT
            echo "    This documentation is auto-generated from the command line." >> $OUT
            echo "" >> $OUT
            echo "## now" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/index.html >> $OUT
            echo "" >> $OUT
            echo "## now init" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/init.html >> $OUT
            echo "" >> $OUT
            echo "## now list" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/list.html >> $OUT
            echo "" >> $OUT
            echo "## now eval" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/eval.html >> $OUT
            echo "" >> $OUT
            echo "## now run" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/run.html >> $OUT
            echo "" >> $OUT

            echo "Updated CLI docs."
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
        "test-cycle"
        "test-dry-run"
        "test-env"
        "test-error"
        "test-flake"
        "test-glob"
        "test-jobs"
        "test-matrix"
        "test-nix-config"
        "test-nixpkgs"
        "test-overlay"
        "test-skip"
        "test-tempdir"
        "test-timeout"
        "test-upload"
        "test-var-script"
        "test-vars"
      ];
      steps = [
        {
          shell = pkgs.nushell;
          run = ''
            print $"(ansi green)Good to go! ^u^(ansi reset)"
          '';
        }
      ];
    };

    test-abort = {
      name = "Test abort";
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

    test-flake = {
      name = "Test flake";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            now run --flake .now/tests
            if $env.LAST_EXIT_CODE != 0 {
              print $"(ansi red_bold)ERROR:(ansi reset) Test failed"
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
              now run $pattern --workflow .now/tests/glob.nix
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

    test-timeout = {
      name = "Test job timeout";
      steps = [
        {
          path = [ now ];
          shell = pkgs.nushell;
          run = ''
            let result = (now run --workflow .now/tests/timeout.nix | complete)
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

            if not ($output | str contains "timed out after 5s") {
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
  };
}
