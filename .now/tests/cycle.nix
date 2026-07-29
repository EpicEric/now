{
  jobs = {
    a = {
      steps = [ { run = "echo a"; } ];
    };
    b = {
      needs = [
        "a"
        "d"
      ];
      steps = [ { run = "echo b"; } ];
    };
    c = {
      needs = [ "b" ];
      steps = [ { run = "echo c"; } ];
    };
    d = {
      needs = [ "c" ];
      steps = [ { run = "echo d"; } ];
    };
  };
}
