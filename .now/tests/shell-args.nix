{
  jobs.shellArgs = { pkgs, ... }: {
    steps = [
      {
        shell = pkgs.bashNonInteractive;
        shellArgs = [ "-f" ];
        run = "echo * * *";
      }
    ];
  };
}
