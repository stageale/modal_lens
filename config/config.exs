import Config

config :axiom_refiner,
       Src.Interface.Isabelle.HPCConnect,
  cluster: :aion,
  ssh_alias: "aion",
  hpc_work_dir: "axiom_refiner_runtime",
  vault_dir: "axiom_refiner_vault",
  remote_base_dir: "axiom_refiner_runs",
  isabelle_bin: "isabelle",
  threads: 8,
  connect_opts: []
