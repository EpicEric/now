{
  default = "script";

  jobs.script = { pkgs, ... }: {
    steps = [
      {
        shell = pkgs.python313;
        run = ./script.py;
      }
    ];
  };
}
