{ runner, ... }:
{
  default = [ "reuse" ];

  jobs.reuse = {
    env.SECRET_VAR = runner.secret "SHARED_VAR";
    steps = [
      {
        env.REGULAR_VAR = runner.var "SHARED_VAR";
        run = "echo This shouldn't run";
      }
    ];
  };
}
