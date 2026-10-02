<p align="center">
    <a href="https://now.dev.br" target="_blank"><img src="https://now.dev.br/images/logo.png" alt="now logo" /></a> <br>
</p>

---

Nix-based distributed command runner.

Check out <https://now.dev.br> for full documentation, including a quick start guide.

You can find examples of how now is used in [`now.nix`](./now.nix) and [`.now/`](./.now).

## Status

Still a work-in-progress. Expect breaking changes between minor versions.

> [!Note]
> LLM disclaimer: This repo includes minor contributions from large language models, all of them thoroughly reviewed by a human.

## Features

- Write workflows, jobs, and steps in Nix for full flexibility
- Distributed execution across local and remote SSH builders
- Declare job dependency graphs, or how concurrent get distributed with job matrices
- Granular control with sandboxing and checkout strategies
- Manage environment secrets and variables
- Share artifacts between jobs via the Nix store
- Per-job timeouts, teardown scripts, dry-runs, and more

## Tests

now is tested with itself. At the root of this repo, run:

```bash
BUILDERS='ssh://localhost - - 1 1 now now -' nix run . -- run test
```
