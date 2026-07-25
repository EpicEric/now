{
  jobs = {
    nixpkgs =
      { pkgs, ... }:
      {
        steps = [
          {
            run = ''
              python3 --version
            '';
            path = [
              pkgs.python3
            ];
          }
        ];
      };
  };
}
