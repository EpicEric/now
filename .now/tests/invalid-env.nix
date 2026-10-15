{
  default = "invalid";
  jobs.invalid.steps = [
    {
      env."🫪" = "distorted face";
      run = "echo This shouldn't run";
    }
  ];
}
