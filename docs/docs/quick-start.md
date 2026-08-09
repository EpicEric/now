---
icon: lucide/rocket
---

# Quick start

## Installation

The recommended way to install now is via Nix (`nix profile add github:EpicEric/now`) or via [crates.io](https://crates.io/crates/now-runner/).

!!! tip

    To try it out without installing, you can use `nix run github:EpicEric/now`.

now comes with a binary cache as well. If you have a multi-user Nix installation, add the following to `/etc/nix/nix.conf`:

```
extra-substituters = https://cache.eric.dev.br
extra-trusted-public-keys = cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=
```

### NixOS installation

=== "tack"

    ```bash
    tack add now github:EpicEric/now --fetch
    ```

    ```nix
    # configuration.nix
    let
      inputs = import ./.tack;
    in
    {
      # ...
      nix.settings = {
        extra-substituters = [ "https://cache.eric.dev.br" ];
        extra-trusted-public-keys = [
          "cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE="
        ];
      };
      environment.systemPackages = [
        (import inputs.now { })
      ];
    }
    ```

=== "npins"

    ```bash
    npins add github EpicEric now
    ```

    ```nix
    # configuration.nix
    let
      sources = import ./npins;
    in
    {
      # ...
      nix.settings = {
        extra-substituters = [ "https://cache.eric.dev.br" ];
        extra-trusted-public-keys = [
          "cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE="
        ];
      };
      environment.systemPackages = [
        (import sources.now { })
      ];
    }
    ```

=== "Nix flake"

    ```nix
    # flake.nix
    {
      inputs = {
        # ...
        now.url = "github:EpicEric/now/main";
      };

      outputs =
        {
          nixpkgs,
          now,
          ...
        }@inputs:
        {
          nixosConfigurations."your-hostname" = nixpkgs.lib.nixosSystem {
            modules = [
              # ...
              ({ pkgs, ... }: {
                nix.settings = {
                  extra-substituters = [ "https://cache.eric.dev.br" ];
                  extra-trusted-public-keys = [
                    "cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE="
                  ];
                };
                environment.systemPackages = [
                  now.packages.${pkgs.stdenv.hostPlatform.system}.default
                ];
              })
            ];
          };
        };
    }
    ```

## Quick start

=== "Standalone (recommended)"

    To get started with now, you can initialize a basic workflow at `now.nix` in the current directory:

    ```bash
    now init
    ```

    Now run its default job:

    ```bash
    now run
    ```

=== "Nix flake"

    To get started with now in a Nix flake, add the following to your outputs:

    ```nix
    # flake.nix
    {
      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
      };

      outputs =
        { nixpkgs, self, ... }:
        {
          # ...

          now = { runner, ... }: {
            inherit nixpkgs;
            default = [ "default" ];
            jobs.default = { pkgs, ... }: {
              steps = [
                {
                  run = ''
                    python3 -c 'print("Hello from now!")'
                  '';
                  path = [
                    pkgs.python313
                  ];
                }
              ];
            };
          };
        };
    }
    ```

    When you run now, specify the flake reference, and an optional attribute path `#path.to.workflow` (defaults to `#now`):

    ```bash
    now run --flake .
    ```
