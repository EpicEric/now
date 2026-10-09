{ promise, types, ... }: {
  options = {
    enable = {
      type = types.bool;
      description = "Whether to use a sandbox for the step.";
    };
    gcroots = {
      type = types.bool;
      description = "Whether the sandboxed step can write Nix GC roots to the configured GC root directory.";
    };
    networkAccess = {
      type = types.bool;
      description = "Whether the sandboxed step has network access.";
    };
    useHome = {
      type = types.either types.bool (types.listOf types.string);
      description = ''
        Whether the sandboxed step can use the runner user's HOME directory.

        You can also pass a list of specific directories to mount as writable
        (eg. `[ ".config/application" ]`).
      '';
    };
    writableDirectory = {
      type = types.bool;
      description = "Whether the sandboxed step can write to the checked-out directory.";
    };
    writableNixStore = {
      type = types.bool;
      description = "Whether the sandboxed step can create derivations on the Nix store.";
    };
  };

  result = promise ({ options }: options);

  meta.description = ''
    The sandbox submodule allows you to specify extra restrictions at
    a job or step level.

    Any step settings override job settings. For example, this allows you to configure
    sandboxing for all steps in a job with `sandbox.enable = true;`, then loosen
    permissions on individual steps that have to write to the filesystem.

    On Linux, [`bubblewrap`](https://github.com/containers/bubblewrap) is used;
    on macOS, `sandbox-exec` is used.
  '';
}
