defmodule Src.Interface.Isabelle.HpcConnect do
  @moduledoc """
  Remote Isabelle execution backend via penthooose/hpc_connect.

  This module should stay thin:
  it receives the same workdir/spec as the local backend
  and returns the same {:ok, log} / {:error, reason} shape.
  """

  def run(workdir, spec, opts \\ []) do
    # TODO
  end

  defp bootstrap(cluster, username, key_path, opts) do
    # TODO
  end

  defp upload_workdir(_session, _workdir, _remote_dir, _opts) do
    # TODO
  end

  defp run_remote_isabelle(_session, _remote_dir, _spec, _isabelle, _threads, _opts) do
    # TODO
  end

  defp maybe_download_log(_session, _remote_dir, _workdir, _opts) do
    # TODO
  end
end
