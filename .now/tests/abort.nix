{
  jobs = {
    # Fails after '_5'
    fail = {
      needs = [ "_5" ];
      steps = [ { run = "exit 63"; } ];
    };
    # Can only start after the failure; should be aborted
    late = {
      needs = [ "_19" ];
      steps = [ { run = "echo 'late ran'; exit 1"; } ];
    };
  }
  // (builtins.listToAttrs (
    builtins.genList (x: {
      name = "_${toString x}";
      value = {
        needs = if x > 0 then [ "_${toString (x - 1)}" ] else [ ];
        steps = [ { run = "echo '=> ${toString x}'"; } ];
      };
    }) 20
  ));
}
