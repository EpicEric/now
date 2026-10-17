{ types, ... }: {
  options = {
    requiredSystemFeatures = {
      type = types.listOf types.string;
    };
    jobKey = {
      type = types.string;
    };
    terminationTimeout = {
      type = types.int;
    };
  };
}
