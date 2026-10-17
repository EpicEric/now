{
  default = [ "graceful-termination" ];

  jobs.graceful-termination = {
    steps = [
      {
        run = ''
          marker=/tmp/now-graceful-termination.marker
          rm -f "$marker"

          cleanup() {
            echo "cleaning" > "$marker"
            sleep 1
            echo "finished" > "$marker"
            exit 143
          }
          trap cleanup TERM

          echo "step: started"

          sleep 300 &
          wait $!
        '';
        teardown = ''
          echo "teardown: marker=$(cat /tmp/now-graceful-termination.marker 2>/dev/null || echo missing)"
          rm -f /tmp/now-graceful-termination.marker
        '';
      }
    ];
  };
}
