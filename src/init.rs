pub(crate) static SHEBANG_NOW_IN_PATH: &str = r"#!/usr/bin/env -S now";

pub(crate) static SHEBANG_NOW_NOT_IN_PATH: &str = r"#! /usr/bin/env nix
#! nix shell git+https://codeberg.org/now-runner/now --command now";

pub(crate) static INIT_TEMPLATE: &str = r#"
{ runner, lib, ... }: {
  name = "My workflow";
  default = [ "default" ];
  jobs = {
    default = { pkgs, ... }: {
      name = "My job";
      steps = [
        {
          name = "My step";
          run = ''
            python3 -c 'print("Hello from now!")'
          '';
          path = [
            pkgs.python3
          ];
        }
      ];
    };
  };
}
"#;
