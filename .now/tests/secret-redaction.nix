{ runner, ... }:
{
  default = [ "redact" ];

  jobs.redact = {
    env.MY_SECRET = runner.secret "MY_SECRET";
    steps = [
      {
        run = ''
          echo "plain: $MY_SECRET"
          echo "embedded: prefix-$MY_SECRET-suffix"
        '';
      }
    ];
  };
}
