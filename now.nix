{ runner, ... }:
let
  mkNow = pkgs: import ./. { inherit pkgs; };
in
{
  default = [ "test" ];

  jobs = {
    test = {
      name = "Run tests";
      needs = [
        "test-abort"
        "test-cycle"
        "test-env"
        "test-error"
        "test-jobs"
        "test-matrix"
        "test-nixpkgs"
        "test-upload"
        "test-vars"
      ];
      steps = [ { run = "echo Good to go! ^u^"; } ];
    };

    format = { pkgs, ... }: {
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
        }
      ];
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
              now run --abort .now/tests/abort.nix || error_code=$?
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
              now run --abort .now/tests/cycle.nix || error_code=$?
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
              now run .now/tests/env.nix
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
              now run --eval .now/tests/error.nix

              now run .now/tests/error.nix || error_code=$?
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
              now run --job b --job x .now/tests/jobs.nix
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
                  --builders "$BUILDERS" \
                  .now/tests/matrix.nix
              else
                echo "BUILDERS is unset; skipping."
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
              # Your Python3 version
              now run .now/tests/nixpkgs.nix

              # now's Python3 version
              now run .now/tests/nixpkgs.nix --nixpkgs '(import ./.tack).nixpkgs'
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
              now run .now/tests/upload.nix
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
              now run .now/tests/vars.nix
            '';
          }
        ];
      };
  };
}
