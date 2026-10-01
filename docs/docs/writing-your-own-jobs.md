---
icon: lucide/pencil-ruler
---

# Writing your own jobs

This page fills in some gaps from the [Quick start](./quick-start.md) so you can start making your own workflows, jobs, and steps.

!!! tip

    To make the most out of `now`, it's recommended that you first familiarize yourself with [the Nix language](https://nixos.org/).

## Where does `now.nix` go?

`now run` looks for a `now.nix` file in the current directory. `now init` creates it there. If your workflow lives somewhere else, point `now` at it with `--workflow`:

```bash
now run --workflow path/to/now.nix
```

Or if you're using a flake:

```bash
now run --flake path/to/flake#now
```

## Writing your own jobs

Open the `now.nix` that `now init` created (or find the `now` output that you added to your flake). The part you'll change most is the `run` string, which contains the script that gets run by a shell:

```nix
{
  jobs.my-second-job = { pkgs, ... }: {
    steps = [
      {
        run = ''
          echo "Do your thing here"
        '';
      }
    ];
  };
}
```

Run it with:

```bash
now run my-second-job
```

## What is `pkgs`?

Your job function automatically receives a `pkgs` argument, populated with an instance of `<nixpkgs>`. You can add packages to a step's PATH:

```nix
{
  jobs.build-docs = { pkgs, ... }: {
    steps = [
      {
        path = [ pkgs.zola ];
        run = "zola build";
      }
    ];
  };
}
```

Or you can run your script on an entirely different shell.

```nix
{
  jobs.countdown = { pkgs, ... }: {
    steps = [
      {
        shell = pkgs.nushell;
        run = ''
          for i in 10..1 {
            print $"(ansi green)($i)!(ansi reset)"
            sleep 1sec
          }
          'Liftoff!' | ansi gradient -F rainbow
        '';
      }
    ];
  };
}
```

## Two ways to write a job

A job can be a plain attribute set (for steps that only need bash), or a function that receives `pkgs`:

```nix
{
  jobs.hello-plain = {
    steps = [ { run = "echo hi"; } ];
  };

  jobs.hello-function = { pkgs, ... }: {
    steps = [ { path = [ pkgs.hello ]; run = "hello"; } ];
  };
}
```

## Checking your workflow

Before running, you can check that your workflow is valid:

```bash
now list           # list the available jobs
now eval           # print the workflow as JSON
now run --dry-run  # see the jobs flow without actually running any steps
```

## Guide

Read on to the [Configuration guide](./configuration.md) for advanced usage.
