{
  ci,
  pkgs,
  lib,
  ...
}:
let
  rust-overlay =
    import (fetchTarball "https://github.com/oxalica/rust-overlay/archive/master.tar.gz") pkgs
      { };

  cix = system: import ../. { inherit system; };
in
{
  jobs = {
    build =
      ci.matrix
        [
          { runner = "x86_64-linux"; }
          { runner = "aarch64-linux"; }
          { runner = "aarch64-darwin"; }
        ]
        (
          { runner }: {
            name = "Build on ${runner}";
            runs-on = runner;
            steps = [ (ci.steps.build "cix" (cix runner)) ];
          }
        );

    rustfmt-msrv = {
      name = "Check rustfmt formatting on MSRV";
      steps = [
        {
          name = "Run rustfmt";
          run = ''
            cargo fmt --check --all
          '';
          path = [
            rust-overlay.rust-bin.stable."1.88.0".default
          ];
        }
      ];
    };

    tests-nightly =
      ci.matrix
        [
          { runner = "aarch64-linux"; }
          { runner = "aarch64-darwin"; }
        ]
        (
          { runner }:
          {
            name = "Run tests on nightly (${runner})";
            strategy.fail-fast = false;
            runs-on = runner;
            steps = [
              {
                name = "Test";
                env = {
                  RUSTFLAGS = "-A dead_code -A unused_variables";
                };
                run = ''
                  cargo nextest run --no-fail-fast --verbose --locked
                '';
                path = [
                  (rust-overlay.rust-bin.selectLatestNightlyWith (toolchain: toolchain.default))
                  pkgs.cargo-nextest
                ]
                ++ lib.optionals (runner == "x86_64-darwin" || runner == "aarch64-darwin") [ pkgs.lld ];
              }
            ];
          }
        );

    coverage-nightly = {
      name = "Test coverage on nightly";
      runs-on = "x86_64-linux";
      steps = [
        {
          name = "Test with coverage";
          env = {
            RUSTFLAGS = "-A dead_code -A unused_variables";
          };
          run = ''
            cargo llvm-cov nextest --no-fail-fast --verbose --codecov --locked --output-path codecov.json
          '';
          path = [
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
            codecovcli do-upload -f ./codecov.json --token "$CODECOV_TOKEN"
          '';
          path = [
            pkgs.codecov-cli
          ];
        }
      ];
    };

    build-docker =
      ci.matrix
        [
          { runner = "x86_64-linux"; }
          { runner = "aarch64-linux"; }
        ]
        (
          { runner, ... }: {
            name = "Build Docker";
            runs-on = runner;
            needs = [
              "build"
              "rustfmt-msrv"
              "tests-nightly"
              "coverage-nightly"
            ];
            steps = [
              (ci.steps.upload "docker-${runner}" (
                pkgs.dockerTools.buildImage {
                  name = "cix";
                  tag = "latest";
                  config.Entrypoint = [ (lib.getExe (cix runner)) ];
                }
              ))
            ];
          }
        );

    push-docker = {
      name = "Build Docker";
      needs = [
        "build-docker"
      ];
      steps = [
        {
          name = "Login to DockerHub";
          env.DOCKERHUB_PUSH_TOKEN = ci.secrets.DOCKERHUB_PUSH_TOKEN;
          run = ''
            echo $DOCKERHUB_PUSH_TOKEN | docker login --password-stdin --username ${ci.vars.DOCKERHUB_USERNAME} docker.io
          '';
          teardown = ''
            docker logout docker.io
          '';
          path = [
            pkgs.docker
          ];
        }
        {
          name = "Login to GHCR";
          env = {
            GITHUB_TOKEN = ci.secrets.GITHUB_TOKEN;
          };
          run = ''
            echo $GITHUB_TOKEN | docker login --pasword-stdin --username ${ci.vars.GITHUB_USERNAME} ghcr.io
          '';
          teardown = ''
            docker logout ghcr.io
          '';
          path = [
            pkgs.docker
          ];
        }
        {
          name = "Push images";
          env = {
            TAGS = builtins.concatStringsSep " " (
              map ({ image, tag }: "${image}:${tag}") (
                lib.cartesianProduct {
                  image = [
                    "${ci.vars.DOCKERHUB_USERNAME}/cix"
                    "ghcr.io/${ci.vars.GITHUB_USERNAME}/cix"
                  ];
                  tag = [
                    "latest"
                    "main"
                  ];
                }
              )
            );
          };
          run = ''
            amd_image=$(cix download docker-x86_64-linux)
            arm_image=$(cix download docker-aarch64-linux)

            for TAG in $TAGS; do
              skopeo copy docker-archive:$amd_image "docker://$TAG-amd64"
              skopeo copy docker-archive:$arm_image "docker://$TAG-arm64"
              docker buildx imagetools create --tag "$TAG" "$TAG-amd64" "$TAG-arm64"
            done
          '';
          path = [
            pkgs.docker-buildx
            pkgs.skopeo
          ];
        }
      ];
    };
  };
}
