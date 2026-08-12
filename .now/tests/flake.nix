{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    { nixpkgs, self, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      eachSystem =
        f:
        (builtins.foldl' (
          acc: system:
          let
            fSystem = f system;
          in
          builtins.foldl' (
            acc': attr:
            acc'
            // {
              ${attr} = (acc'.${attr} or { }) // fSystem.${attr};
            }
          ) acc (builtins.attrNames fSystem)
        ) { } systems);
    in
    eachSystem (system: {
      packages.${system}.default = nixpkgs.legacyPackages.${system}.hello;
    })
    // {
      now = { runner, ... }: {
        inherit nixpkgs;
        default = "flake";
        jobs.flake = { pkgs, ... }: {
          steps = [
            { run = "pwd"; }
            (runner.steps.build {
              name = "hello";
              deriv = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
            })
          ];
        };
      };
    };
}
