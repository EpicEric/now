{ runner, ... }:
{
  jobs = {
    push-to-niks3 =
      { pkgs, ... }:
      let
        now = import ../. { };
      in
      {
        steps = [
          {
            env = {
              NIKS3_SERVER_URL = runner.var "NIKS3_SERVER_URL";
              NIKS3_AUTH_TOKEN = runner.secret "NIKS3_AUTH_TOKEN";
              NIKS3_AUTH_TOKEN_FILE = "/tmp/niks3-token-${toString builtins.currentTime}";
            };
            path = [
              pkgs.niks3
            ];
            run = ''
              echo $NIKS3_AUTH_TOKEN > $NIKS3_AUTH_TOKEN_FILE
              niks3 push ${now}
            '';
            teardown = ''
              rm $NIKS3_AUTH_TOKEN_FILE
            '';
          }
        ];
      };
  };
}
