{ types, ... }:
{
  options = {
    name = {
      type = types.nullOr types.string;
      default = null;
      description = "Name of the workflow";
    };
    on = {
      type = types.attrs;
      default = { };
    };
    jobs = {
      type = types.attrsOf (
        types.union [
          types.null
          job
        ]
      );
      description = "Jobs in the workflow.";
    };
  };

  impl = { options }: options;
}
