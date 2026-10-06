---
icon: lucide/cooking-pot
---

# Cookbook

A collection of common patterns used with `now`.

## Using `now`'s binary cache

A cache containing pre-built binaries is available with the following configuration:

```
extra-substituters = https://cache.eric.dev.br
extra-trusted-public-keys = cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=
```

Additionally, the `NIX_CONFIG` environment variable gets forwarded to local and remote builders, so you can use the cache in arbitrary jobs:

```bash
export NIX_CONFIG='extra-substituters=https://cache.eric.dev.br extra-trusted-public-keys=cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE='
now run distributed-job --builders 'ssh://remote'
```

## Using in GitHub Actions

```yaml
on:
  push:
    branches: ["main"]

jobs:
  now:
    name: Run CI through now
    strategy:
      fail-fast: false
      matrix:
        include:
          - runner: ubuntu-24.04
            system: x86_64-linux
          - runner: ubuntu-24.04-arm
            system: aarch64-linux
          - runner: macos-26
            system: aarch64-darwin
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false
      - name: Install Nix
        uses: NixOS/nix-installer-action@62c1943b776c509394b550f3f983adc14e9212d6 # v1.0.0
        with:
          add-channel: "true"
      - name: Push to cache
        env:
          CODECOV_TOKEN: ${{ secrets.CODECOV_TOKEN }}
        run: |
          nix run git+https://codeberg.org/now-runner/now -- run ci
```

## Installing jobs as a pre-commit hook

=== "bash / zsh"

    ```bash
    cat > .git/hooks/pre-commit <<EOF
    #! /usr/bin/env nix
    #! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh
    now run format
    EOF
    chmod +x .git/hooks/pre-commit
    ```

=== "fish"

    ```fish
    begin
      echo '#! /usr/bin/env nix'
      echo '#! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh'
      echo 'now run format'
    end > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    ```

=== "nushell"

    ```nushell
    r#'#! /usr/bin/env nix
    #! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh
    now run format
    '# | save --force .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    ```

=== "now"

    ```nix
    {
      install-pre-commit-hook = {
        sandbox.enable = true;
        steps = [
          {
            run = ''
              cat > .git/hooks/pre-commit <<EOF
              #! /usr/bin/env nix
              #! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh
              now run format
              EOF
              chmod +x .git/hooks/pre-commit
            '';
            sandbox.writableDirectory = true;
          }
        ];
      };
    }
    ```

!!! tip

    For a lighter alternative also based on Nix, check out [nixhooks](https://tangled.org/poacher.dev/nixhooks).

## Inline workflows

=== "bash / zsh"

    You can declare workflows with temporary files:

    ```bash
    tmp=$(mktemp)
    echo '{
      default = [ "hello" ];
      jobs.hello = { pkgs, ... }: {
        steps = [
          {
            run = '"''"'
              ${pkgs.hello}/bin/hello
            '"''"';
          }
        ];
      };
    }' > "$tmp"
    now run -w "$tmp"
    rm "$tmp"
    ```

=== "fish"

    You can declare workflows via process substitution:

    ```fish
    now run -w (echo '{
      default = [ "hello" ];
      jobs.hello = { pkgs, ... }: {
        steps = [
          {
            run = '"''"'
              ${pkgs.hello}/bin/hello
            '"''"';
          }
        ];
      };
    }' | psub)
    ```

=== "nushell"

    You can declare workflows with temporary files:

    ```nushell
    let tmp = mktemp
    r#'{
      default = [ "hello" ];
      jobs.hello = { pkgs, ... }: {
        steps = [
          {
            run = ''
              ${pkgs.hello}/bin/hello
            '';
          }
        ];
      };
    }
    '# | save --force $tmp
    now run -w $tmp
    rm $tmp
    ```

## Cross-compilation

```nix
{ runner, ... }:
{
  jobs.cross =
    runner.matrix
    [
      {
        pkgs = import <nixpkgs> {
          hostSystem = "aarch64-linux";
        };
      }
    ]
    (
      { pkgs, ... }: {
        steps = [
          {
            path = [ pkgs.nix-info pkgs.nix ];
            run = "nix-info";
          }
        ];
      }
    );
}
```

Steps are cross-compiled to, and run on, `aarch64-linux` runners (which are specified with the `--builders` flag).

To also specify the build system's architecture, use `import <nixpkgs> { buildSystem = "..."; }`.

## Watching for changes

One way is to combine `watch`/`watchexec`/`fswatch` and bash's `trap`, for example:

```nix
let
  # Build `now` itself, so the steps below can run it (see the quick start
  # for alternative installation methods)
  now = import (builtins.fetchGit {
    url = "https://codeberg.org/now-runner/now";
  }) { };
in
{
  jobs = {
    generate-nix-docs = {
      # ...
    };
    generate-cli-docs = {
      # ...
    };

    serve-docs = { pkgs, ... }: {
      steps = [
        {
          path = [
            now
            pkgs.watchexec
            pkgs.zensical
          ];
          run = ''
            trap 'kill 0' EXIT
            watchexec -w now.nix -w now/types.nix -r now run generate-nix-docs &
            watchexec -w now.nix -w src -r now run generate-cli-docs &
            zensical serve -f docs/zensical.toml
          '';
        }
      ];
    };
  };
}
```

## Re-usable workflows and steps

```nix
{ runner, ... }: {
  # Workflows in `imports` get merged
  imports = [
    ./.now/foo.nix
    ./.now/bar.nix
  ];

  jobs.my-job =
    { pkgs, ... }:
    let
      # Assuming `extraSteps = { step1 = args: ...; step2 = args: ...; };`
      extraSteps = import (
        pkgs.fetchFromCodeberg {
          owner = "EpicEric9";
          repo = "now-steps";
          hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
        }
      );
    in
    {
      steps = [
        (extraSteps.step1 {
          # ...
        })
        (extraSteps.step2 {
          # ...
        })
      ];
    };
}
```

## Running steps in an FHS-compatible environment

```nix
{
  default = "fhs";

  jobs.fhs =
    { pkgs, ... }:
    let
      fhsEnv =
        pkgs.buildFHSEnv {
          name = "fhs-bash";
          targetPkgs = pkgs: [
            pkgs.gtk3
            pkgs.openssl
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];
          runScript = "bash";
          # Required to find the entrypoint of the FHS environment
          meta.mainProgram = "fhs-bash";
        };
    in
    {
      steps = [
        {
          shell = fhsEnv;
          path = [
            pkgs.wget
          ];
          run = ''
            wget -o proprietary-binary https://example.com/downloads/latest-linux-amd64
            chmod +x proprietary-binary
            ./proprietary-binary
          '';
        }
      ];
    };
}
```
