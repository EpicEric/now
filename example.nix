{
  ci,
  pkgs,
  lib,
  ...
}:
let
  rust-overlay = import (
    builtins.fetchTarball "https://github.com/oxalica/rust-overlay/archive/master.tar.gz"
  );
in
{
  jobs = {
    rustfmt-msrv = {
      name = "Check rustfmt formatting on MSRV";
      runs-on = "x86_64-linux";
      steps = [
        (ci.steps.checkout.override { persist-credentials = false; })
        {
          name = "Run rustfmt";
          run = ''
            cargo fmt --check --all
          '';
          packages = [
            rust-overlay.rust-bin.stable."1.88.0".default
          ];
        }
      ];
    };

    tests-nightly =
      ci.matrix
        [
          {
            runner = "aarch64-linux";
          }
          {
            runner = "x86_64-darwin";
          }
          {
            runner = "aarch64-darwin";
          }
          # {
          #   runner = "x86_64-windows";
          # }
        ]
        (
          { runner, ... }: {
            name = "Run tests on nightly (${runner}})";
            strategy.fail-fast = false;
            runs-on = runner;
            steps = [
              (ci.steps.checkout.override { persist-credentials = false; })
              {
                name = "Test";
                env = {
                  RUSTFLAGS = "-A dead_code -A unused_variables";
                };
                run = ''
                  cargo nextest run --no-fail-fast --verbose --locked
                '';
                packages = [
                  (rust-overlay.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default))
                  pkgs.cargo-nextest
                ]
                ++ lib.optionals (runner == "x86_64-darwin" || runner == "aarch64-darwin") [ pkgs.lld ];
              }
            ];
          }
        );

    coverage-nightly = {
      name = "Test coverage on nightly (ubuntu-24.04)";
      runs-on = "x86_64-linux";
      steps = [
        (ci.steps.checkout.override { persist-credentials = false; })
        {
          name = "Test with coverage";
          env = {
            RUSTFLAGS = "-A dead_code -A unused_variables";
          };
          run = ''
            cargo llvm-cov nextest --no-fail-fast --verbose --codecov --locked --output-path codecov.json
          '';
          packages = [
            (rust-overlay.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default))
            pkgs.cargo-llvm-cov
            pkgs.cargo-nextest
          ];
        }
        {
          name = "Upload coverage reports to Codecov";
          env = {
            CODECOV_TOKEN = ci.secrets.CODECOV_TOKEN;
          };
          run = ''
            codecovcli do-upload -f ./codecov.json
          '';
          packages = [
            pkgs.codecov-cli
          ];
        }
      ];
    };

    build-docker = lib.mkIf (ci.github.ref == "refs/heads/main") {
      name = "Build Docker";
      permissions = {
        contents = "read";
        packages = "write";
      };
      needs = [
        "rustfmt-msrv"
        "tests-nightly"
        "coverage-nightly"
      ];
      run = ./build.nix;
      secrets = {
        dockerhub-push-token = ci.secrets.DOCKERHUB_PUSH_TOKEN;
        ghcr-push-token = ci.secrets.GITHUB_TOKEN;
      };
    };
  };
}
