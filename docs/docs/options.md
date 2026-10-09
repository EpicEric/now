---
icon: lucide/square-menu
---

# Options reference

!!! note

    This documentation is auto-generated from the workflow definitions.

## workflow

A workflow is the main definition of your `now` commands.
It allows you to specify multiple scripts (jobs) in a single
source of truth via Nix.


Available options:

### workflow.default

Default job(s) to run for this workflow.

_Type:_ `either<string,listOf<string>>`




### workflow.jobs

Jobs in the workflow.
See the [submodule documentation](#job).


_Type:_ `attrsOf<nullOr<job>>`




### workflow.name

Name of the workflow.

_Type:_ `string`




### workflow.nixpkgs

Nix expression that evaluates to nixpkgs. Defaults to `<nixpkgs>`.

_Type:_ `any`

## job

A job is a set of tasks built and run on a single local or remote runner,
made from any number of sequential steps.

When defined via `runner.matrix`, you can specify several versions of the same job,
which may run concurrently on multiple builders and runners.


Available options:

### job.checkout

Strategy for checking out the directory that the job runs on.
Options are:

- `"default"`- use the runner's current directory.
- `"clone"` - always create a fresh copy of the current directory.
- `"none"` - run in an empty directory.
- `"all"` - same as `"default"`, but ignored files are also copied
over to remote builders.
- `"clone-all"` - same as `"clone"`, but ignored files are also copied
over to remote builders.


_Type:_ `checkoutEnum`

_Default:_

```nix
"default"
```



### job.env

Environment values to make available to steps in this job.

_Type:_ `union<string,struct<nowSecret>,struct<nowDownload>>`




### job.name

Name of the job.

_Type:_ `string`




### job.needs

Jobs that must be completed before running this one.

_Type:_ `either<string,listOf<string>>`




### job.pathLockdown

Whether to lock the script's PATH down to only the packages in each
steps' `path`, ignoring the calling shell's PATH.


_Type:_ `bool`




### job.sandbox

Default sandbox configuration for the steps in this job.
See [the submodule documentation](#sandbox).


_Type:_ `either<bool,attrs>`




### job.steps

Steps to run in this job.
See the [submodule documentation](#step).


_Type:_ `listOf<nullOr<step>>`




### job.strategy

How multiple jobs in a matrix should coordinate.

Possible attributes are:

- `failFast`: Whether a single failing run should cancel the remaining jobs in the matrix.


_Type:_ `struct<strategy>`




### job.timeout

How long to run this job for before marking as failed, eg. `"30m"` or `"1h"`.
By default, jobs can run indefinitely.

The timer doesn't take step realizations or teardowns into account.


_Type:_ `string`

## step

A step is a single, atomic task that's run as part of a job.


Available options:

### step.env

Environment values to make available to this step.

_Type:_ `union<string,struct<nowSecret>,struct<nowDownload>>`




### step.name

Name of the step.

_Type:_ `string`




### step.outputVar

If set, then the standard output of this step will be assigned to the
provided environment variable, and made available to the remaining
steps of the job.


_Type:_ `string`




### step.path

Packages added to the PATH of the script.

_Type:_ `listOf<derivation>`




### step.pathLockdown

Whether to lock the script's PATH down to only the packages in `path`,
ignoring the calling shell's PATH.


_Type:_ `bool`




### step.run

Shell script to run on this step.

_Type:_ `pathLike`




### step.sandbox

Sandbox configuration for this step.
See [the submodule documentation](#sandbox).


_Type:_ `either<bool,attrs>`




### step.shell

The shell to use for this step's scripts.

By default, `bash` will be used.


_Type:_ `derivation`




### step.shellArgs

Arguments passed to the shell used in this step's scripts.

_Type:_ `listOf<string>`




### step.teardown

Shell script to run when tearing down this step.

Jobs always run these, after every step concludes, in reverse order.


_Type:_ `pathLike`

## sandbox

The sandbox submodule allows you to specify extra restrictions at
a job or step level.

Any step settings override job settings. For example, this allows you to configure
sandboxing for all steps in a job with `sandbox.enable = true;`, then loosen
permissions on individual steps that have to write to the filesystem.

On Linux, [`bubblewrap`](https://github.com/containers/bubblewrap) is used;
on macOS, `sandbox-exec` is used.


Available options:

### sandbox.enable

Whether to use a sandbox for the step.

_Type:_ `bool`




### sandbox.gcroots

Whether the sandboxed step can write Nix GC roots to the configured GC root directory.

_Type:_ `bool`




### sandbox.networkAccess

Whether the sandboxed step has network access.

_Type:_ `bool`




### sandbox.useHome

Whether the sandboxed step can use the runner user's HOME directory.

You can also pass a list of specific directories to mount as writable
(eg. `[ ".config/application" ]`).


_Type:_ `either<bool,listOf<string>>`




### sandbox.writableDirectory

Whether the sandboxed step can write to the checked-out directory.

_Type:_ `bool`




### sandbox.writableNixStore

Whether the sandboxed step can create derivations on the Nix store.

_Type:_ `bool`
