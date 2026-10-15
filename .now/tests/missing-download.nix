{ runner, ... }:
{
  default = [ "missing-download" ];

  jobs.missing-download = {
    steps = [
      {
        env.MISSING = runner.download "NO_DOWNLOAD";
        run = ''
          exit 0
        '';
      }
    ];
  };
}
