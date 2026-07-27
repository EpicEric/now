{ runner, ... }:
{
  default = [ "env" ];

  jobs = {
    env =
      { ... }:
      let
        another_name = runner;
        obtuse = {
          spam = runner.secret;
        };
      in
      {
        steps = [
          {
            env = {
              TEST = another_name.var "MY_VAR";
              MY_SECRET = obtuse.spam "MY_SECRET";
              MISSING = "Some value: ${runner.var "NO_VAR"}";
            };
            run = ''
              if [ "$TEST" = "This is a variable" ]; then
                echo "TEST: $TEST"
              else
                exit 1
              fi

              if [ "$MY_SECRET" = "This is a secret" ]; then
                echo "MY_SECRET: $MY_SECRET"
              else
                exit 1
              fi

              if [ "$MISSING" = "Some value: " ]; then
                echo "MISSING: $MISSING"
              else
                exit 1
              fi
            '';
          }
        ];
      };

    skipped =
      { ... }:
      {
        steps = [
          {
            env = {
              # Missing secret should be ignored, as the job doesn't run
              SECRET = runner.secret "NO_SECRET";
            };
            run = ''
              exit 1
            '';
          }
        ];
      };
  };
}
