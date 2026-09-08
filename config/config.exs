import Config

config :modal_lens, :isabelle_hpc,
  ssh_alias: "aion-cluster",
  scheduler: :slurm,
  remote_base_dir: "modal_lens_runs",
  isabelle_bin: "isabelle",
  job: [
    cpus_per_task: 8,
    time_limit: "00:30:00"
  ]

config :modal_lens, :verbalization_hpc,
  ssh_alias: "iris-cluster",
  scheduler: :slurm,
  remote_base_dir: "modal_lens_verbalization",
  job: [
    cpus_per_task: 4,
    gpus: 1,
    time_limit: "00:30:00"
  ]
