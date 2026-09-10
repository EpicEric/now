---
icon: lucide/rectangle-ellipsis
---

# now

![now logo](./images/logo.png)

now is a command runner based on [Nix](https://nixos.org/). It allows for distributed builds of reproducible scripts, with control over how and where they should run.

## Example

now is written in plain Nix, with a structure inspired by GitHub Actions:

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

## Core concepts

now is separated into three levels:

- Workflows: The specification of now and its recipes, similar to a `Makefile` or `justfile`.
- Jobs: Each individual recipe in a workflow. These can depend on other jobs and run on multiple machines at once.
- Steps: The individual scripts run as part of your jobs, normally written in a scripting language like bash or Python.

The `now.nix` file format lets you specify these using Nix. For more information, check out the ["Configuration" page](./configuration.md).
