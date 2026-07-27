import Config

config :axiom_refiner,
       Src.Interface.Isabelle.HPCConnect,
       mode: :local,
       cluster: :aion,
       remote_base_dir: "axiom_refiner_runs",
       isabelle_bin: "isabelle",
       threads: 8,
       native_ssh: false,
       connect_opts: []
