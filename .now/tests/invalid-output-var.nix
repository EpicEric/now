{
  default = "invalid";
  jobs.invalid.steps = [
    {
      run = "echo This shouldn't run";
      outputVar = "🫪";
    }
  ];
}
