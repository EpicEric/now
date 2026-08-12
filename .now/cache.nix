{ runner, ... }:
{
  default = [ "push-to-niks3" ];

  inherit (import ../.tack) nixpkgs;

  jobs = {
    build-now = {
      steps = [
        (runner.steps.upload {
          name = "now";
          deriv = (import ../nix { }).now;
        })
      ];
    };

    build-now-step = {
      steps = [
        (runner.steps.upload {
          name = "now-step";
          deriv = (import ../nix { }).now-step;
        })
      ];
    };

    push-to-niks3 =
      { pkgs, ... }:
      {
        needs = [
          "build-now"
          "build-now-step"
        ];
        steps = [
          {
            name = "Push to niks3 cache";
            env = {
              NOW = runner.download "now";
              NOW_STEP = runner.download "now-step";
              NIKS3_SERVER_URL = runner.var "NIKS3_SERVER_URL";
              NIKS3_AUTH_TOKEN = runner.secret "NIKS3_AUTH_TOKEN";
              NIKS3_AUTH_TOKEN_FILE = "/tmp/niks3-token-${toString builtins.currentTime}";
            };
            path = [
              pkgs.niks3
            ];
            run = ''
              # Create file with token
              touch $NIKS3_AUTH_TOKEN_FILE
              chmod 600 $NIKS3_AUTH_TOKEN_FILE
              echo $NIKS3_AUTH_TOKEN > $NIKS3_AUTH_TOKEN_FILE

              # Push derivations to cache
              niks3 push $NOW $NOW_STEP
            '';
            teardown = ''
              rm $NIKS3_AUTH_TOKEN_FILE
            '';
          }
        ];
      };
  };
}
