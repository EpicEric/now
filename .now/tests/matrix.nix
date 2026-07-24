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

    local = { ... }: {
      steps = [
        {
          run = ''
            printf "Hello from localhost!\npwd: "
            pwd
          '';
        }
      ];
    };

    local-2 = runner.matrix [ { name = "Local job"; } ] (
      { name, ... }: {
        inherit name;
        needs = [ "local" ];
        steps = [
          {
            run = ''
              ls
            '';
          }
        ];
      }
    );

    remote = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      steps = [
        {
          run = ''
            printf "Hello from the remote!\npwd: "
            pwd
          '';
        }
      ];
    };
  };
}
