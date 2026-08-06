import Config

config :modal_lens,
       Src.Interface.Isabelle.HPCConnect,
  cluster: :aion,
  ssh_alias: "aion",
  hpc_work_dir: "modal_lens_runtime",
  vault_dir: "modal_lens_vault",
  remote_base_dir: "modal_lens_runs",
  isabelle_bin: "isabelle",
  threads: 8,
  connect_opts: []
