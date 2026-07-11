{
  system ? builtins.currentSystem,
  inputs ? import ../.tack,
  pkgs ? import <nixpkgs> { inherit system; },
  adios ? import inputs.adios,
}:
let
  inherit (pkgs) lib;
  tree = adios {
    modules = adios.lib.importModules { directory = ./adios; };
  } { };
in
workflow: env:
tree.modules.workflow (workflow {
  inherit pkgs lib;
  ci = {
    secrets = lib.genAttrs env.secrets (name: {
      __cixSecret = name;
    });
  };
})
