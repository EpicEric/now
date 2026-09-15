---
icon: lucide/cooking-pot
---

# Cookbook

## Running now as a pre-commit hook

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

    ```bash
    begin
      echo '#! /usr/bin/env nix'
      echo '#! nix shell git+https://codeberg.org/now-runner/now#now --command /bin/sh'
      echo 'now run format'
    end > .git/hooks/pre-commit
    chmod +x .git/hooks/pre-commit
    ```

## Inline workflows

=== "bash / zsh"

    You can declare workflows with a temporary files:

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
