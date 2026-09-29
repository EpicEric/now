{ runner, ... }: {
  default = "tempdir";
  jobs.tempdir.steps = [
    {
      run = ''
        if [ -n "$MY_SPECIAL_VAR" ]; then
          echo "MY_SPECIAL_VAR shouldn't be set!"
          exit 1
        fi
        echo "Var is unset ..."
      '';
      teardown = ''
        if [ ! -n "$MY_SPECIAL_VAR" ]; then
          echo "MY_SPECIAL_VAR should be set!"
          exit 1
        fi
        if [ -d "$MY_SPECIAL_VAR" ]; then
          echo "MY_SPECIAL_VAR should not point to a directory anymore!"
          exit 1
        fi
        echo "... var is set and tempdir is gone."
      '';
    }
    (runner.steps.tempdir "MY_SPECIAL_VAR")
    {
      run = ''
        echo "MY_SPECIAL_VAR=$MY_SPECIAL_VAR"
        if [ ! -n "$MY_SPECIAL_VAR" ]; then
          echo "MY_SPECIAL_VAR should be set!"
          exit 1
        fi
        if [ ! -d "$MY_SPECIAL_VAR" ]; then
          echo "MY_SPECIAL_VAR should be pointing at a directory!"
          exit 1
        fi
        echo "... var is set and tempdir exists ..."
      '';
      teardown = ''
        if [ ! -f "$MY_SPECIAL_VAR/test.txt" ]; then
          echo "MY_SPECIAL_VAR/test.txt should exist!"
          exit 1
        fi
        if [ "$(cat $MY_SPECIAL_VAR/test.txt)" != "Hello, world!" ]; then
          echo "MY_SPECIAL_VAR/test.txt should have the expected contents!"
          exit 1
        fi
        echo "... created file exists in tempdir ..."
      '';
    }
    {
      run = ''
        echo "... writing file to tempdir ..."
        echo "Hello, world!" > $MY_SPECIAL_VAR/test.txt
      '';
    }
  ];
}
