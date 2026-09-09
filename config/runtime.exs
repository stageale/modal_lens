import Config

# SSH authentication is managed externally by OpenSSH and ssh-agent.
# Scheduler and job defaults are defined per role in config/config.exs.

isabelle_hpc_runtime_options =
  [
    ssh_alias: System.get_env("MODAL_LENS_ISABELLE_HPC_SSH_ALIAS"),
    remote_base_dir: System.get_env("MODAL_LENS_ISABELLE_HPC_REMOTE_BASE_DIR"),
    isabelle_bin: System.get_env("MODAL_LENS_ISABELLE_HPC_ISABELLE_BIN"),
    remote_preamble: System.get_env("MODAL_LENS_ISABELLE_HPC_PREAMBLE")
  ]
  |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

verbalization_hpc_runtime_options =
  [
    ssh_alias: System.get_env("MODAL_LENS_VERBALIZATION_HPC_SSH_ALIAS"),
    remote_base_dir: System.get_env("MODAL_LENS_VERBALIZATION_HPC_REMOTE_BASE_DIR"),
    remote_preamble: System.get_env("MODAL_LENS_VERBALIZATION_HPC_PREAMBLE")
  ]
  |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

config :modal_lens, :isabelle_hpc, isabelle_hpc_runtime_options

config :modal_lens, :verbalization_hpc, verbalization_hpc_runtime_options
