{ runner, ... }:
{
  default = [ "run" ];

  jobs = {
    # runner.var in a run script must be rejected at eval time
    run = { ... }: {
      steps = [
        {
          run = ''
            echo "value: ${runner.var "NO_VAR"}"
          '';
        }
      ];
    };

    # runner.var in a teardown script must be rejected at eval time
    teardown = { ... }: {
      steps = [
        {
          run = ''
            true
          '';
          teardown = ''
            echo "value: ${runner.var "NO_VAR"}"
          '';
        }
      ];
    };
  };
}
