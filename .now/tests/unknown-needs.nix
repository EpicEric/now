{
  default = [ "broken" ];

  jobs.broken = {
    needs = [ "does-not-exist" ];
    steps = [ { run = "echo This shouldn't run"; } ];
  };
}
