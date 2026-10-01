{ runner, ... }: {
  default = "overlay";

  jobs = {
    overlay =
      runner.matrix
        [
          {
            pkgs = import (import ../../.tack).nixpkgs {
              overlays = [
                (final: _: {
                  cooler-hello = final.writeScriptBin "cooler-hello" ''
                    echo "Hello, world. B)"
                  '';
                })
              ];
            };
          }
        ]
        (
          { pkgs, ... }:
          {
            steps = [
              {
                run = ''
                  hello
                  cooler-hello
                '';
                path = [
                  pkgs.hello
                  pkgs.cooler-hello
                ];
              }
            ];
          }
        );
  };
}
