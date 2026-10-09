{ types, envType, ... }: {
  options = {
    placeholderName = {
      type = types.string;
    };
    jobPathLockdown = {
      type = types.bool;
    };
    jobEnv = {
      type = envType;
    };
    jobSandbox = {
      type = types.either types.bool types.attrs;
    };
  };
}
