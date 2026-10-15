{ failFast }:
{ runner, ... }:
{
  default = [ "fail-fast" ];

  jobs = {
    fail-fast =
      runner.matrix
        [
          { label = "local"; }
          {
            label = "remote";
            requiredSystemFeatures = [ "now" ];
          }
        ]
        (
          { label }: {
            strategy = { inherit failFast; };
            checkout = "none";
            steps = [
              {
                run =
                  if label == "local" then
                    ''
                      echo "Doing local work..."
                      sleep 2.0
                      exit 1
                    ''
                  else
                    ''
                      echo "Doing remote work..."
                      sleep 3.0
                      echo "Done with remote work."
                    '';
                teardown =
                  if label == "local" then
                    ''
                      echo "Local teardown"
                    ''
                  else
                    ''
                      echo "Remote teardown"
                    '';
              }
            ];
          }
        );
  };
}
