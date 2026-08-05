{
  default = [ "error" ];

  jobs = {
    error = { ... }: {
      steps = [
        {
          run = ''
            exit 1
          '';
          teardown = ''
            echo ""
            echo "=== note: teardown still runs on error ==="
          '';
        }
        {
          run = ''
            echo "This shouldn't be printed at all!"
          '';
        }
      ];
    };
  };
}
