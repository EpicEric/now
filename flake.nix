{
  description = "Nix-based distributed command runner";

  inputs = { };

  outputs =
    { self, ... }@args:
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

      inputs = import ./.tack {
        overrides = args.tackOverrides or { };
      };
    in
    eachSystem (
      system:
      let
        pkgs = import inputs.nixpkgs { inherit system; };
        inherit
          (import ./nix {
            inherit system pkgs;
            useCache = true;
          })
          now
          now-step
          shell
          ;
      in
      {
        packages.${system} = {
          default = now;
          inherit now now-step;
        };

        apps.${system}.default = {
          type = "app";
          program = pkgs.lib.getExe now;
          inherit (now) meta;
        };

        devShells.${system}.default = shell;
      }
    );
}
