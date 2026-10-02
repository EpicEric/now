---
icon: lucide/server
---

# Local and remote builders

Runners are the machines that execute your workflow jobs. A runner can be the local machine or a remote machine accessible over SSH. The system that builds a job's derivations (the **builder**) and the system that runs them (the **runner**) can be, but not necessarily are, the same machine.

## Distinction between builders and runners

Each job goes through two phases, potentially on different machines:

1. **Building**: derivations (step scripts, sandbox wrappers, included packages) are built and cached. The system that builds is the **builder**.
2. **Running**: the built derivations are executed as steps. The system that runs is the **runner**.

A job selects a builder using `buildSystem` and `requiredSystemFeatures`, and a runner using `hostSystem` and `requiredSystemFeatures`. These are all set automatically based on the `pkgs` passed to the job definition and the `requiredSystemFeatures` variant argument.

Using separate builder and runner machines is useful, for example, in the following scenarios:

- Cross-compilation: build on a fast `x86_64-linux` machine and run on `aarch64-linux`.
- Feature isolation: build on a machine without KVM and run on one that has it.
- Resource constraints: build tests on a beefy server and run on a lightweight VM.

## Configuration

Runners are discovered from the Nix builder settings. By default, now reads `nix config show` to find the `builders` setting, which follows the same format as Nix's [`builders`](https://nix.dev/manual/nix/latest/command-ref/conf-file#conf-builders) configuration:

```
ssh://user@host system-features max-jobs speed-factor features mandatory-features public-host-key
```

If the `builders` setting starts with `@`, it's treated as a path to a file containing builder specifications. If that file doesn't exist, no remote builders are configured.

You can also pass builders explicitly via the `--builders` CLI flag, which accepts the same format and overrides the Nix configuration.

### Parsing

Each builder line is parsed as a space-separated tuple:

| Field                        | Meaning                                                                                  |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| `ssh://user@host`            | SSH URI (prefixed with either `ssh://` or `ssh-ng://`)                                   |
| `aarch64-linux,x86_64-linux` | Comma-separated list of supported build systems (`-` defaults to the local system)       |
| `/path/to/identity`          | SSH identity file (`-` uses the current user's identity)                                 |
| `1`                          | Maximum number of concurrent builds                                                      |
| `1`                          | Speed factor (unused)                                                                    |
| `kvm,benchmark`              | Comma-separated system features the builder advertises (`-` means none)                  |
| `now`                        | Comma-separated mandatory features the builder requires jobs to request (`-` means none) |
| `...`                        | Base64-encoded SSH host key                                                              |

### Local-only and remote-only modes

- `--local-only` skips discovery of remote builders entirely, ensuring jobs only get built/run on the local machine.
- `--remote-only` builds and runs jobs on remote builders only, which is useful if the local machine is only used for coordination.

## Using runners

When a job is ready to run, now automatically iterates over all available builders (local + remote) and selects the first available one that matches the job's requirements.

The selection algorithm races all qualifying builders/runners for a job, and the first one who becomes available is used.

### Builder selection

A builder must satisfy:

- **`buildSystem`** must match the builder's system exactly (for local builders) or be in the builder's list of supported build systems (for remote builders).
- **`requiredSystemFeatures`** must all be present in the builder's advertised `systemFeatures`.
- Additionally for remote builders: the builder's `requiredFeatures` (mandatory features) must all be present in the job's `requiredSystemFeatures`.

### Runner selection

A runner must satisfy:

- **`hostSystem`** must match the builder's system exactly or be listed in the builder's `extra-platforms` (for local builders). For remote builders, it must match the remote's `hostSystem`.
- **`requiredSystemFeatures`** must all be present in the runner's advertised `systemFeatures`.
- Additionally for remote runners: the runner's `requiredFeatures` (mandatory features) must all be present in the job's `requiredSystemFeatures`.

## System requirements and features

### System features

Jobs declare `requiredSystemFeatures` to ensure they land on a suitable machine. Remote builders advertise their features in the Nix builder configuration, and local builders read them from `system-features` in the Nix config.

### Extra platforms

Local runners can also run jobs for platforms listed in `extra-platforms` in the Nix configuration (e.g., via QEMU binfmt emulation). This allows an `x86_64-linux` machine to run `aarch64-linux` jobs without a remote builder.

## Environment variables

There are a couple of differences in how environment variables are handled by local and remote runners:

| Behavior                   | Local runner                                                                                             | Remote runners                                                                                                                                            |
| -------------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Which variables get passed | All variables in the current shell, as well as those defined in the step's `env`.                        | All variables in the remote SSH user's shell, as well as those defined in the step's `env`.                                                               |
| Ambient env security       | The full local shell environment is visible to steps (`SSH_AUTH_SOCK`, cloud credentials, tokens, etc.). | The full remote SSH user's environment is visible to steps (`SSH_CONNECTION`, `SSH_CLIENT`, agent-forwarded `SSH_AUTH_SOCK`, remote user's tokens, etc.). |
| `NOW_GCROOT_DIR`           | Set to the local Nix gcroot directory.                                                                   | Not set. Step scripts fall back to `mktemp -d` on the remote host.                                                                                        |
| Cross-step `output_vars`   | Available to subsequent steps in the same job.                                                           | Available to subsequent steps in the same job.                                                                                                            |

Still, there are a couple of behaviors that are the same regardless of the environment:

- `FORCE_COLOR` / `NO_COLOR`: Set based on whether the local terminal supports color.
- `CI` and `TERM`: Always `true` and `xterm-256color`, respectively.
- `runner.var`: Inlined into derivations at eval time. Values are visible in `/nix/store` on the runner machine.
- `runner.secret`: Passed at runtime, only to steps that request them. Redacted from step log output.
- `step.output_var`: Available to subsequent steps in the same job.

!!! note

    Because local and remote runners inherit different ambient environments, a variable set in your local shell (e.g. `export AWS_ACCESS_KEY_ID=...`) will be available to local steps, but not to remote steps. If a step needs a variable regardless of the type of runner, declare it as a `runner.var` (non-sensitive) or `runner.secret` (sensitive).
