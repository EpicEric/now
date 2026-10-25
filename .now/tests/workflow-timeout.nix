{
  default = [ "timeout" ];

  jobs = {
    timeout = { ... }: {
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
            echo "Sleeping for 5 seconds..."
            sleep 5
            echo "This should only be printed if there's no timeout."
          '';
        }
      ];
    };
  };
}
