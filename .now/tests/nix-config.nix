{ runner, lib, ... }:
{
  default = "nix-config";

  jobs = {
    nix-config =
      { pkgs, ... }:
      {
        steps = [
          (runner.steps.build {
            name = "hello-2";
            deriv = derivation {
              name = "hello-2";
              builder = "/bin/bash";
              args = [
                "-c"
                "/bin/hello > $out"
              ];
              nativeBuildInputs = [
                pkgs.bash
                pkgs.hello
              ];
              inherit (pkgs.stdenv.hostPlatform) system;
            };
            nixConfig.extra-sandbox-paths = [
              "/bin/bash=${lib.getExe pkgs.bash}"
              "/bin/hello=${lib.getExe pkgs.hello}"
            ];
          })
        ];
      };
  };
}
