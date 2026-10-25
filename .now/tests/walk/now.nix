{
  jobs.okay.steps = [
    {
      run = ''
        ls
        if [ "$(ls now.nix | wc -l)" == 1 ]; then
          echo "OK"
        else
          echo "Invalid cwdir: $(pwd)"
          exit 1
        fi
      '';
    }
  ];
}
