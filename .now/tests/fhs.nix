{
  default = "fhs";

  jobs.fhs =
    { pkgs, ... }:
    let
      mkFhs =
        pkgs:
        pkgs.buildFHSEnv {
          name = "fhs-bash";
          targetPkgs = pkgs: [
            pkgs.openssl
            (pkgs.python3.withPackages (ps: [ ps.pip ]))
            pkgs.stdenv.cc.cc.lib
            pkgs.zlib
          ];
          runScript = "bash";
          meta.mainProgram = "fhs-bash";
        };
    in
    {
      steps = [
        {
          shell = mkFhs pkgs;
          path = [
            pkgs.eza
          ];
          run = ''
            echo "=== /usr/bin ==="
            eza /usr/bin/ | grep -e "python3"
            echo ""
            echo "=== /usr/lib ==="
            eza /usr/lib/ | grep -e "gcc" -e "libz" -e "openssl" -e "python3"
          '';
        }
      ];
    };
}
