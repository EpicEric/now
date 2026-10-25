{ runner, ... }:
{
  default = "download";

  jobs = {
    upload = { pkgs, ... }: {
      steps = [
        (runner.steps.upload {
          name = "hello";
          deriv = pkgs.runCommand "hello" { } ''
            echo "Hello from local runner" > $out
          '';
        })
      ];
    };

    download = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      needs = [ "upload" ];
      steps = [
        {
          env.DOWNLOAD = runner.download "hello";
          run = ''
            if [ "$(cat $DOWNLOAD)" = "Hello from local runner" ]; then
              echo "$DOWNLOAD: $(cat $DOWNLOAD)"
            else
              echo "Download didn't match"
              exit 1
            fi
          '';
        }
      ];
    };
  };
}
