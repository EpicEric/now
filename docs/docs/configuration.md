---
icon: lucide/book-marked
---

# Configuration guide

## Workflow

A workflow is the main definition of your now commands. It allows you to specify multiple scripts (jobs) in a single source of truth via Nix.

The main option of a workflow is the `jobs` attribute set, which specifies all jobs that can be run. See [the "Jobs" section](#jobs) for more information.

```nix
{ runner, ... }:
{
  name = "Optional name for the workflow";
  jobs = {
    build-hello = { pkgs, ... }: {
      steps = [ (runner.steps.build { deriv = pkgs.hello; }) ];
    };
  };
}
```

You can pass a `default = [ "foo" "bar" ];` attribute to specify which default jobs to run when none are specified in `now run`. This option also supports a single-string alternative (i.e. `default = "foo";`).

```nix
{
  default = [ "my-default" ];
  jobs = {
    my-default = {
      name = "My default job";
      steps = [ { run = "echo 'Run with `now run` or `now run my-default`'"; } ];
    };
    other = {
      name = "Another job run manually";
      steps = [ { run = "echo 'Run with `now run other`'"; } ];
    };
  };
}
```

As a module, it can be specified as an attribute set, or a function that receives the [`runner` argument](#runner) returning an attrset.

A full definition with additional options can be found in [the "Workflow" section of the "Options" page](./options.md#job).

### nixpkgs

The `nixpkgs` option determines which nixpkgs the workflow is built with. It defaults to `<nixpkgs>`, and the resulting `pkgs` instance is passed as an argument to your job functions. You can set it to any expression that evaluates to a nixpkgs source tree:

```nix
{
  nixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/<revision>.tar.gz";
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  jobs = {
    # ...
  };
}
```

When using a flake, the flake input can be passed directly (see [the quick start](./quick-start.md)):

```nix
{
  inherit nixpkgs;

  jobs = {
    # ...
  };
}
```

Job functions receive a `pkgs` instance for the current system by default, but [`runner.matrix`](#runnermatrix) variants can override it on a per-variant basis.

### runner

`runner` is a special argument passed to your workflow that provides useful runtime options.

#### runner.matrix

`runner.matrix` lets you define a single job that expands into multiple parallel runs with different parameters. It takes a list of variant attribute sets, and a job defined as a function accepting those variants.

Each variant can set:

- `pkgs`: import nixpkgs for a different `system` to target a specific platform.
- `requiredSystemFeatures`: list of system features that the remote must advertise.
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

#### runner.var

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

#### runner.secret

`runner.secret "NAME"` declares a runtime secret. Unlike `runner.var`, it cannot be used in string interpolation; it must always be assigned to an environment variable. Secret values are anonymized in logs: any occurrence of the secret value in step or teardown output is replaced with `***` before being printed.

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
          curl -H "Authorization: Bearer $TOKEN" https://api.example.com/data
        '';
      }
    ];
  };
}
```

Pass the secret at runtime:

```bash
TOKEN="s3cr3t" now run
```

#### runner.download

`runner.download "name"` references a derivation previously uploaded by `runner.steps.upload` in an earlier job. The download path resolves to the store path of the uploaded derivation on the runner that runs this step. This allows sharing build artifacts between steps or jobs, even across different machines.

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

#### runner.steps

`runner.steps` provides special step generators that encapsulate common patterns.

##### runner.steps.tempdir

`runner.steps.tempdir name` is a step that creates a temporary directory, sets the provided `name` environment variable with its path, and automatically removes it and its contents on teardown.

```nix
(runner.steps.tempdir "MY_TEMP_DIR")  # Equivalent to `export MY_TEMP_DIR=/tmp/tmp.XXXXXXXXXX`
```

##### runner.steps.upload

`runner.steps.upload { name, deriv, ... }` creates a step that builds the given derivation and registers its output path under the provided name. The path can then be consumed by other jobs via `runner.download`. The upload mechanism works regardless of whether the consumer runs on the same machine or a different remote runner.

```nix
(runner.steps.upload {
  name = "my-data";
  deriv = pkgs.runCommand "data" {} ''
    echo "hello" > $out
  '';
})
```

##### runner.steps.build

`runner.steps.build { name ? "", deriv, ... }` creates a step that builds the given derivation and adds a GC root to prevent it from being garbage-collected. Unlike `upload`, it does not register the result for download by other jobs, and only verifies that the derivation builds successfully.

```nix
(runner.steps.build {
  name = "some-name";
  deriv = pkgs.hello;
})
```

##### Extra options for build/upload steps

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

- `sandbox`: overrides for the step's [sandbox configuration](#sandboxing). `writableNixStore` and `networkAccess` default to `true` (required to build/upload at all) and can't usefully be turned off, but everything else (`enable`, `useHome`, `writableDirectory`) can be set as needed:

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

## Jobs

A job is a set of tasks built and run on a single local or remote runner, made from any number of sequential steps.

The main option of a job is the `steps` list, which specifies the sequence of steps that must be run for successful execution of the job. See [the "Steps" section](#steps) for more information.

```nix
{ runner, ... }:
{
  default = [ "my-job" ];
  jobs.my-job = { pkgs, ... }: {
    name = "Optional name for the job";
    checkout = "none";
    steps = [
      {
        run = ''
          echo "Hello world" > output.txt
        '';
      }
      {
        run = ''
          cat output.txt
        '';
      }
    ];
  };
}
```

A full definition with additional options can be found in [the "Job" section of the "Options" page](./options.md#job).

### Checkout

The `checkout` option controls how the working directory is set up on the runner before steps execute. This is especially relevant for remote runners, where the project directory must be transferred over the network.

Available strategies:

| Strategy      | Local behavior                                                          | Remote behavior                                                          |
| ------------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `"default"`   | Use the current directory as-is.                                        | Copy tracked files to a remote temporary directory.                      |
| `"clone"`     | Copy tracked files to a local temporary directory.                      | Copy tracked files to a remote temporary directory.                      |
| `"none"`      | Create an empty temporary directory.                                    | Create an empty remote temporary directory.                              |
| `"all"`       | Use the current directory as-is.                                        | Copy all files (including ignored ones) to a remote temporary directory. |
| `"clone-all"` | Copy all files (including ignored ones) to a local temporary directory. | Copy all files (including ignored ones) to a remote temporary directory. |

The `"all"` and `"clone-all"` variants include files that would normally be excluded by `.gitignore`. This is useful when your steps depend on generated files that are excluded from version control.

```nix
{
  jobs = {
    remote-build = {
      # This job runs on a remote aarch64-linux builder
      checkout = "clone";
      steps = [
        { run = "ls"; }
      ];
    };
    standalone = {
      # This job doesn't need the project directory at all
      checkout = "none";
      steps = [
        { run = "echo 'running in an empty directory'"; }
      ];
    };
  };
}
```

### Conditional jobs

Jobs support Nix's `lib.mkIf` for conditional inclusion. When the condition is false, the entire job is omitted from the workflow graph:

```nix
{ lib, ... }: {
  jobs = {
    x64-linux-only =
      (lib.mkIf (builtins.currentSystem == "x86_64-linux") {
        steps = [
          { run = "echo 'this only runs on x86_64-linux'"; }
        ];
      });
  };
}
```

### Job dependencies

Jobs can declare other jobs as prerequisites via the `needs` option, which takes a single job name or a list of job names:

```nix
{
  jobs = {
    lint = {
      steps = [
        { run = "cargo clippy"; }
      ];
    };
    test = {
      needs = [ "lint" ];
      steps = [
        { run = "cargo test"; }
      ];
    };
    deploy = {
      needs = "test";
      steps = [
        { run = "./deploy.sh"; }
      ];
    };
  };
}
```

Dependencies are transitive: running a job also runs its whole dependency chain, and jobs that don't depend on each other can run concurrently. A job that `needs` a matrix job waits for all of its variants.

A job only counts as done when all of its steps succeed. If a job fails, the jobs that depend on it are not run, though unrelated jobs continue unless `--abort` is passed. Referring to an unknown job name in `needs`, or creating a dependency cycle, results in an error.

!!! tip

    Run `now list --tree` to print the workflow's dependency graph in the graphviz `.dot` format.

### Timeouts

Jobs can be given a time limit via the `timeout` option, which takes a duration like `"30m"` or `"1h"`:

```nix
{
  jobs.test = {
    timeout = "10m";
    steps = [
      { run = "cargo test"; }
    ];
  };
}
```

A job that exceeds its timeout is marked as failed, but its teardown scripts still run. The timer only covers running the steps, not realizing them.

To limit a whole `now run` invocation instead of a single job, use the `--timeout` option.

### Matrix

The `jobs` attribute can contain a single job definition or, when using `runner.matrix`, a list of job variants. Each variant runs independently and may target different platforms or system features. See [`runner.matrix`](#runnermatrix) for details.

## Steps

A step is a single, atomic task that’s run as part of a job.

The main part of a step is `run`, which executes the provided script (either inline or a path to a script) in the provided `shell` (by default, bash). A similar `teardown` parameter lets you run scripts in reverse order, mainly for cleanup.

A full definition with additional options can be found in [the "Step" section of the "Options" page](./options.md#step).

### Conditional steps

Individual steps can be conditionally included with `lib.mkIf`. When the condition is false, the step is removed from the step list entirely:

```nix
{
  jobs.conditional-job = { lib, pkgs, ... }: {
    steps = [
      { run = "echo 'this always runs'"; }
      (lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) {
        run = "echo 'this only runs on Linux'";
      })
    ];
  };
}
```

### Environment variables and secrets

Environment variables can be set at both the job and step level via the `env` attribute. Step-level values override job-level values when both define the same key.

Each value in `env` can be:

- A plain string, set literally.
- `runner.var "NAME"`: reads the value from the runtime environment; an error is raised if unset. Supports string interpolation.
- `runner.secret "NAME"`: reads a secret from the runtime environment; an error is raised if unset. The value is anonymized in logs: any occurrence in step or teardown output is replaced with `***`. Does not support interpolation.
- `runner.download "name"`: resolves to the store path of a previously uploaded derivation. Does not support interpolation.

```nix
{
  env = {
    PLAIN = "literal value";
    FROM_ENV = "${runner.var "MY_VAR"} (interpolated)";
    SECRET_TOKEN = runner.secret "TOKEN";
    ARTIFACT_PATH = runner.download "my-artifact";
  };
  run = ''
    echo "$PLAIN"
    echo "$FROM_ENV"
    echo "$SECRET_TOKEN"
    echo "$ARTIFACT_PATH"
  '';
}
```

Environment variables are read from the current shell, as well as via the optional `--env-file` argument, which reads a dotenv file.

You can also set environment variables in a job dynamically, by specifying the `outputVar` argument to a step. The standard output of that step is stored in the provided environment variable, which is made available to subsequent steps:

```nix
{
  steps = [
    {
      run = ''
        echo "discarded" > /dev/null
        echo "42"
      '';
      outputVar = "MY_VALUE";
    }
    {
      run = ''
        echo "10 + 32 = $MY_VALUE"  # Prints 10 + 32 = 42
      '';
    }
  ];
}
```

#### Anonymization behavior

When a step or teardown script outputs a value that was set via `runner.secret`, the step binary replaces every occurrence of that value with `***` in logs. This applies regardless of where the value appears, whether that's inside a larger string, as part of a URL, etc.

## Locking a step's `PATH`

By default, a step's script inherits the calling shell's `PATH`, with the packages in `path` prepended to it. If you want a step to only be able to use the packages in `path`, set `pathLockdown` to `true`:

```nix
{
  jobs.build-site = { pkgs, ... }: {
    steps = [
      {
        path = [ pkgs.zola ];
        pathLockdown = true;
        run = "zola build";
      }
    ];
  };
}
```

You can also set `pathLockdown` at the job level to apply it to every step in the job, then override it at the step level:

```nix
{
  jobs.build-site = { pkgs, ... }: {
    pathLockdown = true;
    steps = [
      {
        pathLockdown = false;
        # We can now use the environment PATH's `git`
        run = "git pull https://codeberg.org/now-runner/now && cd now";
      }
      {
        path = [ pkgs.zola ];
        run = "zola build";
      }
    ];
  };
}
```

### Sandboxing

Sandboxing restricts what a step can access on the runner, providing isolation similar to Nix build sandboxes. On Linux, [`bubblewrap`](https://github.com/containers/bubblewrap) is used; on macOS, `sandbox-exec` is used.

You can configure it at both the job and step level. Step settings override job settings, allowing you to set a restrictive default for all steps in a job and selectively loosen it for individual steps, for example.

```nix
{
  # Enable sandboxing for all steps in this job
  sandbox.enable = true;
  steps = [
    {
      run = ''
        # This step runs with the job's sandbox settings
        echo "sandboxed"
      '';
    }
    {
      # Override sandbox settings for this step
      # Sandboxing still applies from the job configuration
      sandbox = {
        writableDirectory = true;
        networkAccess = true;
      };
      run = ''
        curl https://example.com > output.html
      '';
    }
  ];
}
```

`sandbox = true;` is equivalent to `sandbox = { enable = true; };` with all other options at their defaults.

A full definition with all sandboxing options can be found in [the "Sandbox" section of the "Options" page](./options.md#sandbox).
