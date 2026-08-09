{ runner, ... }:
let
  mkNow = pkgs: import ./. { inherit pkgs; };
in
{
  inherit (import ./.tack) nixpkgs;

  jobs = {

    # ============================================================
    #                             Utils
    # ============================================================

    format = { pkgs, ... }: {
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

    serve-docs = { pkgs, ... }: {
      name = "Serve docs";
      steps = [
        {
          path = [
            (mkNow pkgs)
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

    publish-docs = { pkgs, ... }: {
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

    generate-nix-docs = { pkgs, ... }: {
      name = "Generate Nix docs";
      sandbox.enable = true;
      steps =
        let
          evalOptions =
            type:
            pkgs.lib.evalModules {
              modules = [
                type
              ];
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
          (runner.steps.upload "docs-workflow" (moduleDocs types.workflow))
          (runner.steps.upload "docs-job" (moduleDocs {
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
          }))
          (runner.steps.upload "docs-step" (moduleDocs {
            options.step = pkgs.lib.mkOption {
              description = ''
                A step is a single, atomic task that's run as part of a job.
              '';
              type = types.step {
                evalId = "";
                inherit pkgs;
              };
            };
          }))
          (runner.steps.upload "docs-sandbox" (moduleDocs {
            options.sandbox = pkgs.lib.mkOption {
              description = ''
                The sandbox module allows you to specify extra restrictions at
                a job or step level.

                Any step settings override job settings. For example, this allows you to configure
                sandboxing for all steps in a job with `sandbox.enable = true;`, then loosen
                permissions on individual steps that have to write to the filesystem.

                On Linux, [`bubblewrap`](https://github.com/containers/bubblewrap) is used;
                on macOS, `sandbox-exec` is used.
              '';
              type = types.sandbox;
            };
          }))
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

    generate-cli-docs = { pkgs, ... }: {
      name = "Generate CLI docs";
      sandbox.enable = true;
      steps = [
        (runner.steps.upload "docs-cli" (
          pkgs.runCommand "now-cli"
            {
              nativeBuildInputs = [
                pkgs.to-html
                (mkNow pkgs)
              ];
            }
            ''
              mkdir $out
              to-html --no-prompt "now help" > $out/index.html
              to-html --no-prompt "now help init" > $out/init.html
              to-html --no-prompt "now help run" > $out/run.html
            ''
        ))
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
        "test-jobs"
        "test-matrix"
        "test-nixpkgs"
        "test-timeout"
        "test-upload"
        "test-vars"
      ];
      steps = [ { run = "echo Good to go! ^u^"; } ];
    };

    test-abort =
      { pkgs, ... }:
      {
        name = "Test abort";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --abort --workflow .now/tests/abort.nix --all-jobs || error_code=$?
              if [ "$error_code" -eq 0 ]; then
                echo "Test shouldn't have succeeded!"
                exit 1
              else
                echo ""
                echo "=== hint: if 'fail' is the last job, the test works ==="
              fi
            '';
          }
        ];
      };

    test-cycle =
      { pkgs, ... }:
      {
        name = "Test cycle";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --abort --workflow .now/tests/cycle.nix --all-jobs || error_code=$?
              if [ "$error_code" -eq 0 ]; then
                echo "Test shouldn't have succeeded!"
                exit 1
              else
                echo ""
                echo "=== hint: this means the test works ==="
              fi
            '';
          }
        ];
      };

    test-env =
      { pkgs, ... }:
      {
        name = "Test environment";
        steps = [
          {
            env = {
              MY_VAR = "This is a variable";
              MY_SECRET = "This is a secret";
            };
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --workflow .now/tests/env.nix
            '';
          }
        ];
      };

    test-error =
      { pkgs, ... }:
      {
        name = "Test error exit status";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              # Ensure the test evaluates just fine
              now run --eval --workflow .now/tests/error.nix

              now run --workflow .now/tests/error.nix || error_code=$?
              if [ "$error_code" -eq 0 ]; then
                echo "Test shouldn't have succeeded!"
                exit 1
              else
                echo ""
                echo "=== hint: this means the test works ==="
              fi
            '';
          }
        ];
      };

    test-flake =
      { pkgs, ... }:
      {
        name = "Test flake";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --flake .now/tests
            '';
          }
        ];
      };

    test-jobs =
      { pkgs, ... }:
      {
        name = "Test job dependencies";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run b x --workflow .now/tests/jobs.nix
            '';
          }
        ];
      };

    # To run this, pass an envvar like:
    # BUILDERS='ssh://user@host x86_64-linux - 1 1 now now -'
    test-matrix =
      { pkgs, ... }:
      {
        name = "Test run matrix";
        steps = [
          {
            env.BUILDERS = runner.var "BUILDERS";
            path = [
              (mkNow pkgs)
            ];
            run = ''
              if [ -n "$BUILDERS" ]; then
                now run \
                  --all-jobs \
                  --builders "$BUILDERS" \
                  --workflow .now/tests/matrix.nix
              else
                echo "BUILDERS is unset; skipping"
                echo ""
                echo "=== hint: to run this, pass an envvar like ==="
                echo "    BUILDERS='ssh://user@host x86_64-linux - 1 1 now now -'"
              fi
            '';
          }
        ];
      };

    test-nixpkgs =
      { pkgs, ... }:
      {
        name = "Test nixpkgs";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --workflow .now/tests/nixpkgs.nix
            '';
          }
        ];
      };

    test-skip =
      { pkgs, ... }:
      {
        name = "Test skip non-runnable jobs";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --builders "" --skip --all-jobs --workflow .now/tests/skip.nix
            '';
          }
        ];
      };

    test-timeout =
      { pkgs, ... }:
      {
        name = "Test job timeout";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --workflow .now/tests/timeout.nix || error_code=$?
              if [ "$error_code" -eq 0 ]; then
                echo "Test shouldn't have succeeded!"
                exit 1
              else
                echo ""
                echo "=== hint: this means the test works ==="
              fi
            '';
          }
        ];
      };

    test-upload =
      { pkgs, ... }:
      {
        name = "Test uploads";
        steps = [
          {
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --workflow .now/tests/upload.nix
            '';
          }
        ];
      };

    test-vars =
      { pkgs, ... }:
      {
        name = "Test envvars";
        steps = [
          {
            env = {
              TEST_FIRST_VAR = "first var";
              TEST_FIRST_SECRET = "first secret";
              TEST_SECOND_VAR = "second var";
              TEST_SECOND_SECRET = "second secret";
            };
            path = [
              (mkNow pkgs)
            ];
            run = ''
              now run --workflow .now/tests/vars.nix
            '';
          }
        ];
      };
  };
}
