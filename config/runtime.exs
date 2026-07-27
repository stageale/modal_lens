import Config

hpc_runtime_options =
  [
    cluster: System.get_env("HPC_CONNECT_CLUSTER"),
    username: System.get_env("HPC_CONNECT_USERNAME"),
    key_path: System.get_env("HPC_CONNECT_KEY_PATH"),
    env_file: System.get_env("HPC_CONNECT_ENV_FILE"),
    ssh_alias: System.get_env("HPC_CONNECT_SSH_ALIAS"),
    proxy_jump: System.get_env("HPC_CONNECT_PROXY_JUMP"),
    hpc_work_dir: System.get_env("HPC_CONNECT_WORK_DIR"),
    remote_base_dir: System.get_env("AXIOM_REFINER_HPC_REMOTE_BASE_DIR"),
    isabelle_bin: System.get_env("AXIOM_REFINER_HPC_ISABELLE_BIN"),
    remote_preamble: System.get_env("AXIOM_REFINER_HPC_PREAMBLE")
  ]
  |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

config :axiom_refiner,
       Src.Interface.Isabelle.HPCConnect,
       hpc_runtime_options
