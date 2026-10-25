{ runner, ... }:
{
  jobs = {
    empty = runner.matrix [ ] (
      { ... }: {
        steps = [
          {
            run = ''
              echo "This shouldn't run!"
              exit 1
            '';
          }
        ];
      }
    );

    local = {
      steps = [
        {
          env.SECRET_VALUE = runner.var "VAR_TO_PASS_TO_RUNNERS";
          run = ''
            printf "Hello from localhost!\nsecret value: $SECRET_VALUE\npwd: "
            pwd
          '';
        }
      ];
    };

    local-2 = runner.matrix [ { name = "Local 2"; } ] (
      { name, ... }: {
        inherit name;
        needs = [ "local" ];
        steps = [
          { run = "ls"; }
        ];
      }
    );

    remote = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      steps = [
        {
          env.SECRET_VALUE = runner.var "VAR_TO_PASS_TO_RUNNERS";
          run = ''
            printf "Hello from the remote!\nsecret value: $SECRET_VALUE\npwd: "
            pwd
          '';
        }
      ];
    };

    remote-2 = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      needs = [ "remote" ];
      steps = [
        { run = "ls"; }
      ];
    };
  };
}
