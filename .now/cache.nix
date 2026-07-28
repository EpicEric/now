{ runner, ... }:
{
  jobs = {
    push-to-niks3 =
      { pkgs, ... }:
      {
        steps = [
          (runner.steps.upload "now" (import ../. { }))
          {
            name = "Push to niks3 cache";
            env = {
              NOW = runner.download "now";
              NIKS3_SERVER_URL = runner.var "NIKS3_SERVER_URL";
              NIKS3_AUTH_TOKEN = runner.secret "NIKS3_AUTH_TOKEN";
              NIKS3_AUTH_TOKEN_FILE = "/tmp/niks3-token-${toString builtins.currentTime}";
            };
            path = [
              pkgs.niks3
            ];
            run = ''
              echo $NIKS3_AUTH_TOKEN > $NIKS3_AUTH_TOKEN_FILE
              niks3 push $NOW
            '';
            teardown = ''
              rm $NIKS3_AUTH_TOKEN_FILE
            '';
          }
        ];
      };
  };
}
