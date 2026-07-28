{ runner, ... }:
let
  upload_key = "upload-key";
in
{
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
            echo Sleeping
            sleep 30
            printf "$FILE: "
            cat $FILE
          '';
        }
      ];
    };
  };
}
