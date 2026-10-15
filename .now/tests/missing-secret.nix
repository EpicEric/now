{ runner, ... }:
{
  default = [ "missing-secret" ];

  jobs.missing-secret = {
    steps = [
      {
        env.MISSING = runner.secret "NO_SECRET";
        run = ''
          exit 0
        '';
      }
    ];
  };
}
