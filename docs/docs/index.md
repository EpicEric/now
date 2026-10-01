---
icon: lucide/rectangle-ellipsis
---

# now

![now logo](./images/logo.png){.now-logo}

now is a command runner based on [Nix](https://nixos.org/). It allows for distributed builds of reproducible scripts, with control over how and where they should run.

## Examples

=== "Serve and build a static website"

    ```nix
    {
      default = [ "serve" ];

      jobs = {
        build = { pkgs, ... }: {
          name = "Build";
          steps = [
            {
              path = [ pkgs.zola ];
              run = "zola build";
            }
            {
              run = "echo Done!";
            }
          ];
        };

        serve = { pkgs, ... }: {
          name = "Serve";
          steps = [
            {
              path = [ pkgs.zola ];
              run = ''
                echo Press Ctrl-C to quit.
                zola serve
              '';
            }
          ];
        };
      };
    }
    ```

=== "Run development tasks in sandboxes"

    ```nix
    {
      # Run all tasks with just `now run check`
      check = {
        needs = [
          "lint"
          "format"
          "build"
          "test"
        ];
      };

      lint = { pkgs, ... }: {
        steps = [
          {
            run = ''
              cargo clippy --fix --all --allow-dirty
            '';
            path = [
              pkgs.cargo
              pkgs.clippy
            ];
            sandbox = {
              enable = true;
              writableDirectory = true;
            };
          }
        ];
      }

      format = { pkgs, ... }: {
        needs = [ "lint" ];
        steps = [
          {
            run = ''
              cargo fmt --all
            '';
            path = [
              pkgs.cargo
              pkgs.rustfmt
            ];
            sandbox = {
              enable = true;
              writableDirectory = true;
            };
          }
        ];
      };

      build = { pkgs, ... }: {
        needs = [ "lint" ];
        # Create a fresh temporary directory for builds
        checkout = "clone";
        steps = [
          {
            run = ''
              cargo build
            '';
            path = [
              pkgs.cargo
              pkgs.rustc
            ];
            sandbox.enable = true;
          }
        ];
      };

      test = { pkgs, ... }: {
        needs = [ "build" ];
        steps = [
          {
            run = ''
              cargo nextest run
            '';
            path = [
              pkgs.cargo
              pkgs.cargo-nextest
              pkgs.rustc
            ];
            sandbox.enable = true;
          }
        ];
      };
    }
    ```

=== "Distributed Docker builds"

    ```nix
    { runner, ... }: {
      jobs.docker =
        runner.matrix
        [
          {
            pkgs = import <nixpkgs> { system = "x86_64-linux"; };
            requiredSystemFeatures = [ "docker" ];
          }
          {
            pkgs = import <nixpkgs> { system = "aarch64-linux"; };
            requiredSystemFeatures = [ "docker" ];
          }
        ]
        (
          { pkgs, ... }:
          let
            inherit (pkgs.stdenv.hostPlatform) system;
          in
          {
            name = "Docker (${system})";
            steps = [
              (runner.steps.upload {
                name = "docker-image-${system}";
                deriv = pkgs.dockerTools.buildLayeredImage {
                  name = "docker.io/${runner.var "DOCKERHUB_USERNAME"}/hello";
                  tag = system;
                  config.Entrypoint = [ (lib.getExe pkgs.hello) ];
                };
              })
              {
                name = "Login to DockerHub";
                env = {
                  DOCKERHUB_PUSH_TOKEN = runner.secret "DOCKERHUB_PUSH_TOKEN";
                  DOCKERHUB_USERNAME = runner.var "DOCKERHUB_USERNAME";
                };
                run = ''
                  echo $DOCKERHUB_PUSH_TOKEN | docker login --password-stdin --username $DOCKERHUB_USERNAME docker.io
                '';
                teardown = ''
                  docker logout docker.io
                '';
                path = [ pkgs.docker ];
              }
              {
                name = "Push image";
                env.DOCKER_IMAGE = runner.download "docker-image-${system}";
                run = "docker push $DOCKER_IMAGE";
                path = [ pkgs.docker ];
              }
            ];
          }
        );
      };
    }
    ```

## Core concepts

now is separated into three levels:

- :lucide-workflow:{ .md .middle } **Workflows:** The specification of now and its recipes. Inspired by [GitHub Actions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), with a touch of [`just`](https://just.systems/man/en/).
- :lucide-clipboard-list:{ .md .middle } **Jobs:** Each individual recipe in a workflow. These can depend on other jobs and run on multiple machines at once.
- :lucide-layers:{ .md .middle } **Steps:** The individual scripts run as part of your jobs, normally written in a scripting language like bash or Python.

The `now.nix` file format lets you specify these using Nix.
