adios:
adios {
  modules = {
    job = import ./job.nix adios;
    step = import ./step.nix adios;
    workflow = import ./workflow.nix adios;
  };
}
