{ runner, ... }:
let
  thisSystem = builtins.currentSystem;
  unavailableSystem = "x86_64-unknown-freebsd";
in
{
  jobs = {
    a = {
      steps = [ { run = "echo a"; } ];
    };
    b =
      runner.matrix
        [
          {
            pkgs = import <nixpkgs> {
              system = unavailableSystem;
              crossSystem.config = thisSystem;
            };
          }
        ]
        {
          steps = [ { run = "echo b; exit 1"; } ];
        };
    c = {
      needs = [ "b" ];
      steps = [ { run = "echo c; exit 1"; } ];
    };
    d = {
      needs = [
        "a"
        "c"
      ];
      steps = [ { run = "echo d; exit 1"; } ];
    };

    v = {
      steps = [ { run = "echo v"; } ];
    };
    w = {
      needs = [ "v" ];
      steps = [ { run = "echo w"; } ];
    };
    x =
      runner.matrix
        [
          {
            pkgs = import <nixpkgs> {
              system = thisSystem;
              crossSystem.config = unavailableSystem;
            };
          }
        ]
        {
          needs = [ "w" ];
          steps = [ { run = "echo x; exit 1"; } ];
        };
    y = {
      needs = [ "x" ];
      steps = [ { run = "echo y; exit 1"; } ];
    };
    z = {
      needs = [ "y" ];
      steps = [ { run = "echo z; exit 1"; } ];
    };
  };
}
