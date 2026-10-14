adios:
adios {
  modules = {
    workflow = import ./workflow.nix adios;
    job = import ./job.nix adios;
    step = import ./step.nix adios;
    sandbox = import ./sandbox.nix adios;
  };
}
