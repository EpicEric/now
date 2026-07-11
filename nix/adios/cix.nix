{ types, ... }:
{
  options = {
    cix = {
      type = types.derivation;
      defaultFunc = { inputs }: (import ../. { inherit (inputs.nixpkgs) pkgs; }).cix;
    };
  };

  inputs = {
    nixpkgs = {
      path = "/nixpkgs";
    };
  };
}
