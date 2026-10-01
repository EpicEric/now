# Changelog

## Unreleased

### Breaking changes

- Rename `sandbox.writablePath` to `sandbox.writableDirectory`

### Added

- Add `now-step` via overlay to `pkgs` instances
  - The default behavior is to prefer any pre-existing version of `now-step`. This can be overriden at build time with `NOW_WITH_LOCAL_STEP=true`.

### Changed

- Pass envvars to `now-step` via stdin
- Don't pass `NOW_GCROOT_DIR` to remote builders
- Handle SSH host keys for remote builders

## 0.4.0 (2026-09-29)

### Breaking changes

- Remove args/flags from `now run`:
  - `--nixpkgs`: specify it directly in the workflow
  - `--eval`: replaced with the `now eval` command
  - `--use-cache`: See <https://now.dev.br/cookbook/#using-nows-binary-cache>
- `runner.var` now fails on missing environment variables

### Added

- Allow passing a boolean to the sandbox option
- Support flakes
- Add `--skip` flag
- Add `all` and `clone-all` checkout strategies
- Add assertions
- Add `--gcroot-dir` flag
- Mount the GC root directory into sandboxed steps
- Concurrent builds and add `--cores` option
- Add exclusive lock for running jobs
- Match jobs by glob
- Forward NIX_CONFIG envvar to builders
- Add `outputVar` to step definition
- Add `runner.steps.tempdir`
- Add `--dry-run` flag
- Add `now list` command
- Add `now list --tree` flag
- Add `now run --dry-run` test

### Fixed

- Fix job skipping

### Changed

- Refactor `runner.steps`
- Make more paths async
- Keep GC roots out of step derivations
- Derive eval ID from the workflow source
- Cache now-step and use it in workflow.nix

## 0.3.0 (2026-08-05)

### Breaking changes

- Rename `jobs.<job>.strategy.fail-fast` to `jobs.<job>.strategy.failFast`
- Don't run all jobs by default
- Remove `--checkout` argument from `now run`: specify it directly in the workflow

### Added

- Add clone checkout strategy
- Add timeout to jobs
- Add `--remote-only` flag
- Support sandboxing on Darwin

### Fixed

- Fix debug run and remote builds
- Smarter cwdir selection

### Changed

- Clean up project directory when workflow eval is terminated
- Update license text
- Move sandbox options into the workflow
- Bake sandbox into built derivations

## 0.2.2 (2026-08-02)

### Added

- Add cycle-detection test
- Add `--use-cache` flag
- Add `--timeout` and `--tracing` flags
- Auto-complete workflow and jobs in shell
- Check if terminal supports color
- Serialize workflow to JSON and propagate color support
- Instrument spans where it makes sense
- Experimental sandboxing

### Fixed

- Limit host name size on logs
- Don't check the entire graph after every job
- Use `evalModules` for jobs and steps
- Use `.tar.gz` archive that respects gitignore for embedded project source
- Fix upload handling

### Changed

- Set now.nix as the default workflow path
- Separate build and host halves

## 0.2.1 (2026-07-29)

### Added

- Add `--abort` flag
- Add binary cache
- Add gcroots on build/upload steps
- Use ControlMaster for SSH builders whenever possible

### Fixed

- Improve line-splitting logic in step

## 0.2.0 (2026-07-27)

### Breaking changes

- Use `runner.var` and `runner.secret` functions for envvars and secrets, respectively

### Fixed

- Better concurrency for jobs and fd management for steps
- Fix line handling in now-step

### Changed

- Add evalId to workflow evaluations

## 0.1.1 (2026-07-26)

Post-launch fixes.

## 0.1.0 (2026-07-26)

Initial release.
