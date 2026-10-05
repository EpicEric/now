{ ... }:
{
  default = [
    "step-level"
    "job-level"
    "step-override"
  ];

  jobs = {
    step-level =
      { pkgs, ... }:
      {
        steps = [
          {
            path = [ pkgs.hello ];
            pathLockdown = true;
            run = ''
              hello

              # `now` is not in this step's path
              if command -v now >/dev/null 2>&1; then
                echo "ERROR: now should not be on the locked PATH"
                exit 1
              fi
            '';
          }
        ];
      };

    job-level =
      { pkgs, ... }:
      {
        pathLockdown = true;
        steps = [
          {
            path = [ pkgs.hello ];
            run = ''
              hello

              if command -v now >/dev/null 2>&1; then
                echo "ERROR: now should not be on the locked PATH"
                exit 1
              fi
            '';
          }
        ];
      };

    step-override =
      { pkgs, ... }:
      {
        pathLockdown = true;
        steps = [
          {
            path = [ pkgs.hello ];
            pathLockdown = false;
            run = ''
              hello

              # `now` is in the calling shell's PATH
              command -v now >/dev/null
            '';
          }
        ];
      };
  };
}
