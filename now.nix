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
      sandbox.enable = true;
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
          sandbox.writablePath = true;
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
            trap 'kill 0' EXIT
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
      steps = [
        {
          sandbox = {
            enable = true;
            writablePath = true;
          };
          path = [
            pkgs.zensical
          ];
          run = ''
            zensical build -f docs/zensical.toml
          '';
        }
        {
          env = {
            DOCS_HOST = runner.secret "DOCS_HOST";
          };
          run = ''
            rsync --delete-after -acP docs/site/ $DOCS_HOST:www
          '';
          path = [
            pkgs.rsync
          ];
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
            sandbox.writablePath = true;
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
              echo "!!! note" >> $OUT
              echo "" >> $OUT
              echo "    This documentation is auto-generated from the workflow definitions." >> $OUT
              echo "## Workflow" >> $OUT
              echo "A workflow is the main definition of your now commands. \
              It allows you to specify multiple scripts (jobs) in a single source of truth via Nix." >> $OUT
              cat $DOCS_WORKFLOW | sed 's/## /### /g' >> $OUT
              echo "## Job" >> $OUT
              cat $DOCS_JOB | sed 's/## /### /g' >> $OUT
              echo "## Step" >> $OUT
              cat $DOCS_STEP | sed 's/## /### /g' >> $OUT
              echo "## Sandbox" >> $OUT
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
                to-html --no-prompt "now help eval" > $out/eval.html
                to-html --no-prompt "now help run" > $out/run.html
              '';
        })
        {
          sandbox.writablePath = true;
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
            echo "!!! note" >> $OUT
            echo "" >> $OUT
            echo "    This documentation is auto-generated from the command line." >> $OUT
            echo "## now" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/index.html >> $OUT
            echo "" >> $OUT
            echo "## now init" >> $OUT
            echo "" >> $OUT
            cat $DOCS_CLI/init.html >> $OUT
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
      name = "Run tests";
      needs = [
        "test-abort"
        "test-cycle"
        "test-env"
        "test-error"
        "test-flake"
        "test-glob"
        "test-jobs"
        "test-matrix"
        "test-nix-config"
        "test-nixpkgs"
        "test-skip"
        "test-timeout"
        "test-upload"
        "test-var-script"
        "test-vars"
      ];
      steps = [ { run = "echo Good to go! ^u^"; } ];
    };

    test-abort = {
      name = "Test abort";
      steps = [
        {
          path = [ now ];
          run = ''
            error_code=0
            output=$(now run --abort --workflow .now/tests/abort.nix --all-jobs 2>&1) || error_code=$?

            if [ "$error_code" -eq 0 ]; then
              echo "ERROR: Test shouldn't have succeeded!"
              exit 1
            fi

            for i in 0 1 2 3 4 5; do
              if ! echo "$output" | grep -qF "=> $i"; then
                echo "ERROR: Expected '=> $i' in output, but got:"
                echo "$output"
                exit 1
              fi
            done

            if echo "$output" | grep -qF "late ran"; then
              echo "ERROR: 'late' job should have been aborted, but it ran:"
              echo "$output"
              exit 1
            fi

            echo "Test passed."
          '';
        }
      ];
    };

    test-cycle = {
      name = "Test cycle";
      steps = [
        {
          path = [ now ];
          run = ''
            error_code=0
            output=$(now run --abort --workflow .now/tests/cycle.nix --all-jobs 2>&1) || error_code=$?

            if [ "$error_code" -eq 0 ]; then
              echo "ERROR: Test shouldn't have succeeded!"
              exit 1
            fi

            if ! echo "$output" | grep -qF "Cycle detected"; then
              echo "ERROR: Expected a 'Cycle detected' error, but got:"
              echo "$output"
              exit 1
            fi

            echo "Test passed."
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
          run = ''
            now run --workflow .now/tests/env.nix
          '';
        }
      ];
    };

    test-error = {
      name = "Test error exit status";
      steps = [
        {
          path = [ now ];
          run = ''
            # Ensure the test evaluates just fine
            now eval --workflow .now/tests/error.nix

            error_code=0
            output=$(now run --workflow .now/tests/error.nix --all-jobs 2>&1) || error_code=$?

            if [ "$error_code" -eq 0 ]; then
              echo "ERROR: Test shouldn't have succeeded!"
              exit 1
            fi

            if ! echo "$output" | grep -qF "=== note: teardown still runs on error ==="; then
              echo "ERROR: Expected teardown note in output, but got:"
              echo "$output"
              exit 1
            fi

            if echo "$output" | grep -qF "This shouldn't be printed at all!"; then
              echo "ERROR: Steps after a failed step should not run, but got:"
              echo "$output"
              exit 1
            fi

            echo "Test passed."
          '';
        }
      ];
    };

    test-flake = {
      name = "Test flake";
      steps = [
        {
          path = [ now ];
          run = ''
            now run --flake .now/tests
          '';
        }
      ];
    };

    test-glob = {
      name = "Test job globbing";
      steps = [
        {
          path = [ now ];
          run = ''
            now run "a/1*" --workflow .now/tests/glob.nix
            now run "b/**/*" --workflow .now/tests/glob.nix
            now run "c/f?o" --workflow .now/tests/glob.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-jobs = {
      name = "Test job dependencies";
      steps = [
        {
          path = [ now ];
          run = ''
            now run b x --workflow .now/tests/jobs.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-matrix = {
      name = "Test run matrix";
      steps = [
        {
          path = [ now ];
          run = ''
            if [ -n "$BUILDERS" ]; then
              now run \
                --all-jobs \
                --builders "$BUILDERS" \
                --workflow .now/tests/matrix.nix
              echo "Test passed."
            else
              echo "WARNING: BUILDERS is unset; skipping"
              echo ""
              echo "=== hint: to run this, pass an envvar like:"
              echo "===   BUILDERS='ssh://user@host x86_64-linux - 1 1 now now -'"
            fi
          '';
        }
      ];
    };

    test-nix-config = {
      name = "Test nixConfig";
      steps = [
        {
          path = [ now ];
          run = ''
            now run --workflow .now/tests/nix-config.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-nixpkgs = {
      name = "Test nixpkgs";
      steps = [
        {
          path = [ now ];
          run = ''
            now run --workflow .now/tests/nixpkgs.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-skip = {
      name = "Test skip non-runnable jobs";
      steps = [
        {
          path = [ now ];
          run = ''
            now run --builders "" --skip --all-jobs --workflow .now/tests/skip.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-timeout = {
      name = "Test job timeout";
      steps = [
        {
          path = [ now ];
          run = ''
            error_code=0
            output=$(now run --workflow .now/tests/timeout.nix 2>&1) || error_code=$?

            if [ "$error_code" -eq 0 ]; then
              echo "ERROR: Test shouldn't have succeeded!"
              exit 1
            fi

            if ! echo "$output" | grep -qF "Done!"; then
              echo "ERROR: Expected the first step to complete before the timeout, but got:"
              echo "$output"
              exit 1
            fi

            if ! echo "$output" | grep -qF "=== note: teardown still runs on timeout ==="; then
              echo "ERROR: Expected teardown note in output, but got:"
              echo "$output"
              exit 1
            fi

            if ! echo "$output" | grep -qF "timed out after 5s"; then
              echo "ERROR: Expected a timeout error, but got:"
              echo "$output"
              exit 1
            fi

            if echo "$output" | grep -qF "This shouldn't be printed at all!"; then
              echo "ERROR: The step that timed out should not have completed, but got:"
              echo "$output"
              exit 1
            fi

            echo "Test passed."
          '';
        }
      ];
    };

    test-upload = {
      name = "Test uploads";
      steps = [
        {
          path = [ now ];
          run = ''
            now run --workflow .now/tests/upload.nix
            echo "Test passed."
          '';
        }
      ];
    };

    test-var-script = {
      name = "Test runner.var disallowed in scripts";
      steps = [
        {
          path = [ now ];
          run = ''
            error_code=0
            output=$(now run --workflow .now/tests/var-script.nix 2>&1) || error_code=$?

            if [ "$error_code" -eq 0 ]; then
              echo "ERROR: Test shouldn't have succeeded!"
              exit 1
            fi

            if ! echo "$output" | grep -q "cannot be used directly in"; then
              echo "ERROR: Expected a 'cannot be used directly in' error, but got:"
              echo "$output"
              exit 1
            fi

            echo "Test passed."
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
          run = ''
            now run --workflow .now/tests/vars.nix
            echo "Test passed."
          '';
        }
      ];
    };
  };
}
