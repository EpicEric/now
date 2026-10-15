{ runner, ... }:
{
  default = [ "remote-job" ];

  jobs = {
    remote-job = runner.matrix [ { requiredSystemFeatures = [ "now" ]; } ] {
      steps = [
        {
          run = "echo This shouldn't run";
          teardown = "echo Teardown shouldn't run";
        }
      ];
    };
  };
}
