{ runner, ... }:
{
  default = [ "missing-var" ];

  jobs.missing-var = {
    steps = [
      {
        env.MISSING = "Some value: ${runner.var "NO_VAR"}";
        run = ''
          exit 0
        '';
      }
    ];
  };
}
