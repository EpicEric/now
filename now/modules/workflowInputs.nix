{ types, ... }: {
  options = {
    mkOverlay = {
      type = types.function;
    };
    terminationTimeout = {
      type = types.int;
    };
  };
}
