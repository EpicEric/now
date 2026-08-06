{
  default = "nixpkgs";

  nixpkgs = (import ../../.tack).nixpkgs;

  jobs = {
    nixpkgs =
      { pkgs, ... }:
      {
        steps = [
          {
            run = ''
              printf "${pkgs.hello}: "
              hello --version | head -n1
            '';
            path = [
              pkgs.hello
            ];
          }
        ];
      };
  };
}
