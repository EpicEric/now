---
icon: lucide/rectangle-ellipsis
---

# now

![now logo](./assets/logo.png)

now is a command runner based on [Nix](https://nixos.org/). It allows for distributed builds, reproducible scripts, and control over how/when they should run.

## Core concepts

now is separated into three levels:

- Workflows: The specification of now and its recipes, similar to a `Makefile` or `justfile`.
- Jobs: Each individual recipe in a workflow. These can depend on other jobs and run on multiple machines at once.
- Steps: The individual scripts run as part of your jobs, normally written in a scripting language like bash or Python.

The `now.nix` file format lets you specify these using Nix. For more information, check out the ["Configuration" page](./configuration.md).
