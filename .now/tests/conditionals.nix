{
  jobs = {
    a = {
      steps = [ { run = "echo 'a'"; } ];
    };
    b =
      if false then
        {
          steps = [ { run = "echo 'b'; exit 1"; } ];
        }
      else
        null;
    c =
      { pkgs, ... }:
      if pkgs ? hello then
        null
      else
        {
          steps = [ { run = "echo 'c'; exit 1"; } ];
        };

    x = {
      steps = [ { run = "echo 'x'"; } ];
    };
    y = {
      needs = [ "x" ];
      steps = [ { run = "echo 'y'"; } ];
    };
    z = {
      needs = [ "y" ];
      steps = [ (if true then null else { run = "echo 'z'; exit 1"; }) ];
    };
  };
}
