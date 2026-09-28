---
icon: lucide/cooking-pot
---

# Cookbook

## Using `now`'s binary cache

A cache containing pre-built binaries is available with the following configuration:

```
extra-substituters = https://cache.eric.dev.br
extra-trusted-public-keys = cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=
```

Additionally, the `NIX_CONFIG` environment variable gets forwarded to local and remote builders, so you can use the cache in arbitrary jobs:

```bash
NIX_CONFIG='extra-substituters=https://cache.eric.dev.br extra-trusted-public-keys=cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=' \
  now run distributed-job --builders 'ssh://remote'
```

## Using `now` in GitHub Actions

```yaml
on:
  push:
    branches: ["main"]

jobs:
  push-to-cache:
    name: Push to cache
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
          CACHE_URL: ${{ vars.CACHE_URL }}
          CACHE_TOKEN: ${{ secrets.CACHE_TOKEN }}
        run: |
          nix run git+https://codeberg.org/now-runner/now -- run push-to-cache
```

## Running jobs as a pre-commit hook

=== "bash / zsh"

    ```bash
    echo > .git/hooks/pre-commit <<EOF
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
      { pkgs, ... }:
      {
        path = [ pkgs.nix ];
        run = "nix-info";
      }
    );
}
```

Steps are cross-compiled and run on `aarch64-linux` runners.

To also specify the build system's architecture, use `import <nixpkgs> { buildSystem = "..."; }`.

## Watching for changes

One way is to combine `watch`/`watchexec`/`fswatch` and bash's `trap`, for example:

```nix
{
  jobs = {
    generate-nix-docs = {
      # ...
    };
    generate-cli-docs = {
      # ...
    };

    serve-docs = {
      steps = [
        {
          path = [
            pkgs.now
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
  };
}
```
