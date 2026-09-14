{
  jobs = {
    # glob: a/1*
    "a/1" = {
      steps = [ { run = "echo a/1"; } ];
    };
    "a/11" = {
      steps = [ { run = "echo a/11"; } ];
    };
    "a/12" = {
      steps = [ { run = "echo a/12"; } ];
    };
    "a" = {
      steps = [ { run = "echo a; exit 1"; } ];
    };
    "a/" = {
      steps = [ { run = "echo a/; exit 1"; } ];
    };
    "a/21" = {
      steps = [ { run = "echo a/21; exit 1"; } ];
    };

    # glob: b/**/*
    "b/1" = {
      steps = [ { run = "echo b/1"; } ];
    };
    "b/11" = {
      steps = [ { run = "echo b/11"; } ];
    };
    "b/1/1" = {
      steps = [ { run = "echo b/1"; } ];
    };
    "b/1/1/1" = {
      steps = [ { run = "echo b/1/1/1"; } ];
    };
    "b" = {
      steps = [ { run = "echo b"; } ];
    };
    "b1" = {
      steps = [ { run = "echo b1; exit 1"; } ];
    };

    # glob: c/f?o
    "c/foo" = {
      steps = [ { run = "echo c/foo"; } ];
    };
    "c/flo" = {
      steps = [ { run = "echo c/flo"; } ];
    };
    "c" = {
      steps = [ { run = "echo c; exit 1"; } ];
    };
    "c/f" = {
      steps = [ { run = "echo c/f; exit 1"; } ];
    };
    "c/fo" = {
      steps = [ { run = "echo c/fo; exit 1"; } ];
    };
    # <https://github.com/rust-lang/glob/issues/190>
    # "c/f/o" = {
    #   steps = [ { run = "echo c/f/o; exit 1"; } ];
    # };
  };
}
