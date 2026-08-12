{ runner, ... }:
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
              inherit (pkgs.stdenv.hostPlatform) system;
            };
            nixConfig.extra-sandbox-paths = [
              "/bin/bash=${pkgs.bash}/bin/bash"
              "/bin/hello=${pkgs.hello}/bin/hello"
            ];
          })
        ];
      };
  };
}
