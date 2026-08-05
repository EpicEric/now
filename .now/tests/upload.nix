{ runner, ... }:
let
  upload_key = "upload-key";
in
{
  default = [ "read" ];

  jobs = {
    write = { pkgs, ... }: {
      steps = [
        (runner.steps.upload upload_key (pkgs.writeText "example" "Hello, world!"))
        {
          name = "stat";
          env.UPLOADED = runner.download upload_key;
          run = ''
            stat $UPLOADED
          '';
        }
      ];
    };

    read = { ... }: {
      needs = [ "write" ];
      steps = [
        {
          name = "read";
          env.FILE = runner.download upload_key;
          run = ''
            printf "$FILE: "
            cat $FILE
          '';
        }
      ];
    };
  };
}
