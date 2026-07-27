{
  jobs = {
    fail = {
      steps = [ { run = "exit 63"; } ];
    };
  }
  // (builtins.listToAttrs (
    builtins.genList (x: {
      name = "_${toString x}";
      value = {
        steps = [ { run = "echo '=> ${toString x}'"; } ];
      };
    }) 6
  ));
}
