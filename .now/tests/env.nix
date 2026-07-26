{ runner, ... }:
{
  jobs = {
    env =
      { ... }:
      let
        another_name = runner;
        obtuse = {
          spam = runner;
        };
      in
      {
        steps = [
          {
            env = {
              TEST = another_name.vars.MY_VAR;
              inherit (obtuse.spam.secrets) MY_SECRET;
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
            '';
          }
        ];
      };
  };
}
