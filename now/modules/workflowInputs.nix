{ types, ... }: {
  options = {
    overlay = {
      type = types.function;
    };
    terminationTimeout = {
      type = types.int;
    };
  };
}
