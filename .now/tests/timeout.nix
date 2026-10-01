{
  default = [ "timeout" ];

  jobs = {
    timeout = { ... }: {
      timeout = "3s";
      steps = [
        {
          run = ''
            echo "Sleeping for 0.1 seconds..."
            sleep 0.1
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
