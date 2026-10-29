# Changelog

## 0.6.4 (2026-10-29)

### Fixed

- Handle local runner's `extra-platforms` for builder discovery
- Secure temporary directories from other users

### Changed

- Use `ssh-ng://` instead of `ssh://`
- Shorten remote runner names in logs
- Improve `now init` template generation
- Improve pre-eval parsing speed
- Prefer using store path over embedding the project source
- Update dependencies

## 0.6.3 (2026-10-23)

### Fixed

- Improve logging on error conditions and remote runners
- Instrument futures with spans correctly
- Fix cross-compilation in the overlay

## 0.6.2 (2026-10-19)

### Added

- Shebang support

## 0.6.1 (2026-10-18)

### Fixed

- Fix nested signal passing
- Fix signal handling in `now-step`

## 0.6.0 (2026-10-17)

### ⚠️ Breaking changes

- Migrate module system to adios
  - `evalModules` helpers such as `lib.mkIf` will no longer work. Use plain conditionals instead
  - Top-level `imports` will no longer work. Use `lib.recursiveUpdate` instead

### Added

- Add `pathLockdown` to jobs/steps
- Allow passing a script file to `run`/`teardown`
- Add `--logging` option
- List jobs that were aborted when `strategy.failFast = true`
- Add `--termination-timeout` option for graceful termination

### Fixed

- Use pinned nixpkgs to build now-step
- Fix handling of sandbox options
- Proper matrix job cancellation with `strategy.failFast = true`
- Fix `--timeout` behavior
- Consolidate logs for `now`-specific steps
- Fix lingering remote steps

### Changed

- Respect TMPDIR variable in remote runners
- Use binary wrappers for run/teardown derivations
- Order suggestions by Levenshtein score
- Raise minimum Levenshtein score for suggestions
- Shorten logs by omitting `step` prefix
- Include `pkgs.coreutils` in all steps

## 0.5.0 (2026-10-04)

### ⚠️ Breaking changes

- Rename `sandbox.writablePath` to `sandbox.writableDirectory`

### Added

- Add `now-step` via overlay to `pkgs` instances
  - The default behavior is to prefer any pre-existing version of `now-step`. This can be overriden at build time with `NOW_WITH_LOCAL_STEP=true`
- Add parameter to `--tracing` to control colored output in traces
- Add `--keep-alive` option

### Fixed

- Fix provided SSH identity not being used for remote realizations
- Improve ANSI color handling

### Changed

- Pass envvars to `now-step` via stdin
- Don't pass `NOW_GCROOT_DIR` to remote builders
- Handle SSH host keys for remote builders
- Force ANSI colors when running on certain CI runners
- Improve logging when no jobs in the workflow match
- Improve traces in jobs and capture errors

## 0.4.0 (2026-09-29)

### ⚠️ Breaking changes

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

### ⚠️ Breaking changes

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

### ⚠️ Breaking changes

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
