---
icon: lucide/square-play
---

# The `runner` API

`runner` is a special argument passed to your workflow that provides useful runtime options.

## runner.matrix

`runner.matrix` lets you define a single job that expands into multiple parallel runs with different parameters. It takes a list of variant attribute sets, and a job defined as a function accepting those variants.

Each variant can set:

- `pkgs`: import nixpkgs for a different `system` to target a specific platform.
- `requiredSystemFeatures`: list of system features that the remote must be registered with.
- Any extra attributes, which become function arguments in the job definition.

```nix
{ runner, ... }:
{
  jobs.my-matrix-job =
    runner.matrix
    [
      { pkgs = import <nixpkgs> { system = "aarch64-linux"; }; }
      { requiredSystemFeatures = [ "kvm" ]; }
      { spam = "with eggs"; }
    ]
    ({ pkgs, spam ? null, ... }: {
      name = "Matrix job (${if spam != null then spam else pkgs.stdenv.hostPlatform.system})";
      env.SYSTEM = pkgs.stdenv.hostPlatform.system;
      strategy.failFast = false;
      steps = [
        {
          run = ''
            echo "running on $SYSTEM"
          '';
        }
      ];
    });
}
```

The `strategy` submodule controls how matrix runs coordinate:

- `strategy.failFast` (default: `true`): whether a single failing run cancels the remaining jobs.

## runner.var

`runner.var "NAME"` declares a runtime attribute that is read from the environment when `now run` is invoked. If the variable is not set, an error is raised. Because it returns a plain string, it can be used in string interpolation, but only inside `env` blocks.

```nix
{ runner, ... }: {
  default = [ "example" ];
  jobs.example = {
    steps = [
      {
        env.MESSAGE = "${runner.var "MESSAGE"} (from the environment)";
        run = ''
          echo "$MESSAGE"
        '';
      }
    ];
  };
}
```

Pass the value at runtime:

```bash
MESSAGE="Hello" now run
```

!!! warning

    `runner.var` variables will be baked into derivations at build time, meaning that they will end up in the Nix store. Don't use these for sensitive data.

!!! note

    If you want an environment variable to be optional, use it directly in your script without going through `runner.var`:

    ```nix
    {
      jobs.missing.steps = [
        {
          run = ''
            if [ -n "$MAYBE_SET" ]; then
              echo "Variable is: $MAYBE_SET"
            else
              echo "Variable is not set"
            fi
          '';
        }
      ];
    }
    ```

    Both of these commands run successfully:

    ```bash
    MAYBE_SET="My text here" now run missing
    now run missing
    ```

## runner.secret

`runner.secret "NAME"` declares a runtime secret. Unlike `runner.var`, it cannot be used in string interpolation, and it must always be assigned to an environment variable. Secret values are anonymized in logs; any occurrence of the secret value in a step's output is replaced with `***` before being printed.

```nix
{ runner, ... }: {
  default = "example";
  jobs.example = {
    steps = [
      {
        env = {
          TOKEN = runner.secret "TOKEN";
        };
        run = ''
          # The value of $TOKEN will be anonymized if printed
          curl -vH "Authorization: Bearer $TOKEN" https://api.example.com/data
        '';
      }
    ];
  };
}
```

Pass the secret at runtime:

```bash
TOKEN="pk-s3cr3t" now run
```

## runner.download

`runner.download "name"` references a derivation previously uploaded by `runner.steps.upload` in an earlier job, and it must also be passed as an environment variable to steps. The download path resolves to the store path of the uploaded derivation. This allows for sharing build artifacts between steps or jobs, even across different machines.

```nix
{ runner, ... }: {
  jobs = {
    builder = {
      steps = [
        (runner.steps.upload {
          name = "my-artifact";
          deriv = pkgs.writeText "data.txt" "hello from builder";
        })
      ];
    };
    consumer = {
      needs = [ "builder" ];
      steps = [
        {
          env.DATA = runner.download "my-artifact";
          run = "cat $DATA";
        }
      ];
    };
  };
}
```

## runner.steps

`runner.steps` provides special step generators that encapsulate common patterns.

### runner.steps.tempdir

`runner.steps.tempdir name` is a step that creates a temporary directory, sets the provided `name` environment variable with its path, and automatically removes it and its contents on teardown.

```nix
(runner.steps.tempdir "MY_TEMP_DIR")  # Equivalent to `export MY_TEMP_DIR=/tmp/tmp.XXXXXXXXXX`
```

### runner.steps.upload

`runner.steps.upload { name, deriv, ... }` creates a step that builds the given derivation and registers its output path under the provided name. The path can then be consumed by other jobs via `runner.download`. The upload mechanism works regardless of whether the consumer runs on the same machine or a different remote runner.

```nix
(runner.steps.upload {
  name = "my-data";
  deriv = pkgs.runCommand "data" {} ''
    echo "hello" > $out
  '';
})
```

### runner.steps.build

`runner.steps.build { name ? "", deriv, ... }` creates a step that builds the given derivation and adds a GC root to prevent it from being garbage-collected. Unlike `upload`, it does not register the result for download by other jobs, and only verifies that the derivation builds successfully.

```nix
(runner.steps.build {
  name = "some-name";
  deriv = pkgs.hello;
})
```

### Extra options for build/upload steps

Both `runner.steps.build` and `runner.steps.upload` accept a few optional attributes on top of `name` and `deriv`:

- `nixConfig`: an attrset of Nix configuration options (in the same format as `nix.conf`), made available to `nix-store --realise` via the `NIX_CONFIG` environment variable. Useful for pointing the step at extra binary caches:

  ```nix
  (runner.steps.build {
    deriv = pkgs.hello;
    nixConfig = {
      extra-substituters = [ "https://cache.eric.dev.br" ];
      extra-trusted-public-keys = [ "cache.eric.dev.br-1:szEyq5LCjxDCUHYSRaSFU5HdHmR7QlT+FRG3tB9QtpE=" ];
    };
  })
  ```

- `env`: additional environment variables for the step, merged with (and overriding) any `NIX_CONFIG` derived from `nixConfig`:

  ```nix
  (runner.steps.build {
    deriv = pkgs.hello;
    env.SOME_VAR = "value";
  })
  ```

- `sandbox`: overrides for the step's [sandbox configuration](./configuration.md#sandboxing). `writableNixStore` and `networkAccess` default to `true` (required to build/upload at all) and can't usefully be turned off, but everything else (`enable`, `useHome`, `writableDirectory`) can be set as needed:

  ```nix
  (runner.steps.upload {
    name = "my-data";
    deriv = pkgs.runCommand "data" {} ''
      echo "hello" > $out
    '';
    sandbox = {
      enable = true;
      useHome = true;
    };
  })
  ```
