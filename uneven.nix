{ ... }:
let
  mkUneven = pkgs: import ./. { inherit pkgs; };
in
{
  jobs = {
    test-vars =
      { pkgs, ... }:
      {
        name = "Test envvars";
        steps = [
          {
            env = {
              TEST_FIRST_VAR = "first var";
              TEST_FIRST_SECRET = "first secret";
              TEST_SECOND_VAR = "second var";
              TEST_SECOND_SECRET = "second secret";
            };
            path = [
              (mkUneven pkgs)
            ];
            run = ''
              uneven run .uneven/tests/vars.nix
            '';
          }
        ];
      };
  };
}
