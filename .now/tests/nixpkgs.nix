{
  jobs = {
    nixpkgs =
      { pkgs, ... }:
      {
        steps = [
          {
            run = ''
              printf "${pkgs.python3}: "
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
