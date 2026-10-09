{ types, ... }: {
  options = {
    requiredSystemFeatures = {
      type = types.listOf types.string;
    };
    jobKey = {
      type = types.string;
    };
  };
}
