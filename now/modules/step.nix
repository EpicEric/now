{
  evalId,
  envType,
  promise,
  types,
  ...
}@adios:

let
  readPath = pathLike: if builtins.isPath pathLike then builtins.readFile pathLike else pathLike;

  runnerVarsRun =
    { options }:
    map builtins.head (
      builtins.filter builtins.isList (
        builtins.split "@@__nowVar_${evalId}_([^@]+)@@" (readPath options.run)
      )
    );

  runnerVarsTeardown =
    { options }:
    if options ? teardown then
      map builtins.head (
        builtins.filter builtins.isList (
          builtins.split "@@__nowVar_${evalId}_([^@]+)@@" (readPath options.teardown)
        )
      )
    else
      [ ];

  invalidEnvs =
    { options, inputs }:
    let
      inherit (inputs.nixpkgs.pkgs.lib) isValidPosixName;
    in
    builtins.filter (name: !isValidPosixName name) (
      builtins.attrNames (inputs.stepInputs.jobEnv // (options.env or { }))
    );
in

{
  inputs = {
    nixpkgs.from = { self }: self.nixpkgs;
    sandbox.from = { self }: self.sandbox;
    stepInputs.from = { self }: self.stepInputs;
  };

  options = {
    name = {
      type = types.string;
      description = "Name of the step.";
    };
    shell = {
      type = types.derivation;
      description = ''
        The shell to use for this step's scripts.

        By default, `bash` will be used.
      '';
    };
    shellArgs = {
      type = types.listOf types.string;
      description = "Arguments passed to the shell used in this step's scripts.";
    };
    run = {
      type = types.pathLike;
      description = "Shell script to run on this step.";
    };
    teardown = {
      type = types.pathLike;
      description = ''
        Shell script to run when tearing down this step.

        Jobs always run these, after every step concludes, in reverse order.
      '';
    };
    path = {
      type = types.listOf types.derivation;
      description = "Packages added to the PATH of the script.";
    };
    pathLockdown = {
      type = types.bool;
      description = ''
        Whether to lock the script's PATH down to only the packages in `path`,
        ignoring the calling shell's PATH.
      '';
    };
    env = {
      type = envType;
      description = "Environment values to make available to this step.";
    };
    sandbox = {
      type = types.either types.bool types.attrs;
      description = ''
        Sandbox configuration for this step.
        See [the submodule documentation](#sandbox).
      '';
    };
    outputVar = {
      type = types.string;
      description = ''
        If set, then the standard output of this step will be assigned to the
        provided environment variable, and made available to the remaining
        steps of the job.
      '';
    };
    ${"__nowUpload_${evalId}"} = {
      type = types.string;
    };
  };

  modules = {
    nixpkgs = import ./nixpkgs.nix adios;
    sandbox = import ./sandbox.nix adios;
    stepInputs = import ./stepInputs.nix adios;
  };

  assertions = [
    {
      verify = { options }: runnerVarsRun { inherit options; } == [ ];
      explain =
        { inputs, options }:
        let
          inherit (inputs.nixpkgs.pkgs.lib) concatStringsSep;
        in
        "${
          concatStringsSep ", " (
            map (var: "`runner.var \"${var}\"`") (runnerVarsRun {
              inherit options;
            })
          )
        } cannot be used directly in run script";
    }
    {
      verify = { options }: runnerVarsTeardown { inherit options; } == [ ];
      explain =
        { inputs, options }:
        let
          inherit (inputs.nixpkgs.pkgs.lib) concatStringsSep;
        in
        "${
          concatStringsSep ", " (
            map (var: "`runner.var \"${var}\"`") (runnerVarsTeardown {
              inherit options;
            })
          )
        } cannot be used directly in teardown script";
    }
    {
      verify =
        { inputs, options }:
        invalidEnvs { inherit inputs options; } == [ ];
      explain =
        { inputs, options }:
        let
          inherit (inputs.nixpkgs.pkgs.lib) concatStringsSep;
        in
        "environment variables ${
          concatStringsSep ", " (map (var: "'${var}'") invalidEnvs { inherit inputs options; })
        } are not valid POSIX variable names";
    }
    {
      verify =
        { inputs, options }:
        let
          inherit (inputs.nixpkgs.pkgs.lib) isValidPosixName;
        in
        if options ? outputVar then isValidPosixName options.outputVar else true;
      explain =
        { options }:
        "output environment variable '${options.outputVar}' is not a valid POSIX variable name";
    }
  ];

  mutations = promise (
    {
      inputs,
      options,
      path,
    }:
    let
      inherit (builtins) isBool;
      inherit (inputs.stepInputs) jobSandbox;
    in
    {
      "${path}/sandbox" =
        if isBool (options.sandbox or false) then
          (if isBool jobSandbox then { } else jobSandbox) // { enable = options.sandbox; }
        else
          (if isBool jobSandbox then { enable = jobSandbox; } else jobSandbox) // options.sandbox;
    }
  );

  result = promise (
    { options, inputs }:
    let
      inherit (inputs.nixpkgs) pkgs;
      inherit (pkgs.lib)
        getExe
        optionalString
        escapeShellArgs
        escapeShellArg
        makeBinPath
        filterAttrs
        ;
      inherit (inputs.stepInputs)
        jobEnv
        jobPathLockdown
        placeholderName
        ;
      script =
        text:
        pkgs.writeTextFile {
          name = "now-step-script";
          text = ''
            #! ${getExe (if options ? shell then options.shell else pkgs.bash)} ${
              optionalString (options ? shellArgs) (escapeShellArgs options.shellArgs)
            }
            ${text}
          '';
          executable = true;
        };
      env = jobEnv // (options.env or { });
      stepPathLockdown = options.pathLockdown or jobPathLockdown;
      lockedPath = escapeShellArg (makeBinPath options.path);
      runtimeInputs = options.path or [ ];
    in
    {
      name = if (options ? name && options.name != "") then options.name else placeholderName;

      runDrv =
        (pkgs.writeShellApplication {
          name = "now-step";
          checkPhase = "";
          inherit runtimeInputs;
          text = ''
            ${optionalString stepPathLockdown "export PATH=${lockedPath}"}
            ${getExe pkgs.now-step} ${
              if options ? "__nowUpload_${evalId}" || options ? outputVar then "--preserve-stdout" else ""
            } ${
              pkgs.callPackage ../sandbox.nix {
                nowSandbox = inputs.sandbox;
                nowScript = script (readPath options.run);
              }
            } ${
              escapeShellArgs (builtins.attrNames (filterAttrs (_: value: value ? "__nowSecret_${evalId}") env))
            }
          '';
        }).drvPath;

      teardownDrv =
        if options ? teardown then
          (pkgs.writeShellApplication {
            name = "now-step";
            checkPhase = "";
            inherit runtimeInputs;
            text = ''
              ${optionalString stepPathLockdown "export PATH=${lockedPath}"}
              ${getExe pkgs.now-step} ${
                pkgs.callPackage ../sandbox.nix {
                  nowSandbox = inputs.sandbox;
                  nowScript = script (readPath options.teardown);
                }
              } ${
                escapeShellArgs (builtins.attrNames (filterAttrs (_: value: value ? "__nowSecret_${evalId}") env))
              }
            '';
          }).drvPath
        else
          null;

      inherit env;

      ${"__nowUpload_${evalId}"} = options."__nowUpload_${evalId}" or null;

      outputVar = options.outputVar or null;
    }
  );

  meta.description = ''
    A step is a single, atomic task that's run as part of a job.
  '';
}
