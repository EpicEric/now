{ runner, ... }:
{
  default = "build";

  jobs = {
    build = { pkgs, ... }: {
      steps = [
        {
          run = "echo NOW_GCROOT_DIR=$NOW_GCROOT_DIR";
        }
        (runner.steps.build {
          name = "my-build";
          deriv = pkgs.writeText "example-build" "Awesome build";
        })
        (runner.steps.upload {
          name = "my-upload";
          deriv = pkgs.writeText "example-upload" "Awesome upload";
        })
      ];
    };
  };
}
