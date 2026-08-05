{
  default = [ "timeout" ];

  jobs = {
    timeout = { ... }: {
      timeout = "5s";
      steps = [
        {
          run = ''
            echo "Sleeping for 1 second..."
            sleep 1
            echo "Done!"
          '';
          teardown = ''
            echo ""
            echo "=== note: teardown still runs on timeout ==="
          '';
        }
        {
          run = ''
            echo "Sleeping for 60 seconds..."
            sleep 60
            echo "This shouldn't be printed at all!"
          '';
        }
      ];
    };
  };
}
