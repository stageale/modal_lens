defmodule Src.Explanation.Verbal.Launcher do
  @moduledoc """
  Creates and launches Python verbalization jobs.
  """

  alias Src.Explanation.Verbal.HPCConnect, as: VerbalHPCConnect
  alias Src.Explanation.Verbal.Job

  @python_module "verbalization.launcher"

  @typedoc "Execution location of the Python verbalization launcher."
  @type execution_backend :: :local | :hpc_connect

  @doc """
  Creates a verbalization job, writes its request file, and runs the Python launcher.
  """
  @spec launch(String.t(), String.t(), String.t(), String.t()) :: {:ok, map}
  def launch(report_path, output_root, backend, model_id, opts \\ []) do
    output_name = Keyword.get_lazy(opts, :output_name, fn -> default_output_name(model_id) end)
    output_directory = Path.join(output_root, output_name)
    job_options = Keyword.take(opts, [:seed, :max_new_tokens, :backend_options])

    with {:ok, job} <- Job.new(backend, model_id, report_path, output_directory, job_options),
         request_path <- Job.build_request_path(output_directory),
         {:ok, request_path} <- Job.write(job, request_path),
         {:ok, response} <- run_request(request_path, opts) do
      {:ok,
       %{
         job: job,
         request_path: request_path,
         response: response
       }}
    end
  end

  @doc "Starts `launch/5` in a separate task."
  @spec launch_async(String.t(), String.t(), String.t(), String.t()) :: Task.t()
  @spec launch_async(String.t(), String.t(), String.t(), String.t(), keyword()) ::
          Task.t()
  def launch_async(report_path, output_root, backend, model_id, opts \\ []) do
    Task.async(fn -> launch(report_path, output_root, backend, model_id, opts) end)
  end

  @doc """
  Runs the Python verbalization launcher for an existing request file.

  Set `:execution_backend` to `:hpc_connect` to submit the request as an Iris
  GPU SLURM job. The default remains `:local`.
  """
  @spec run_request(String.t()) :: {:ok, map()} | {:error, map()}
  @spec run_request(String.t(), keyword()) :: {:ok, map()} | {:error, map()}
  def run_request(request_path, opts \\ []) do
    run_requests([request_path], opts)
  end

  @doc """
  Runs the Python verbalization launcher once for multiple request files.

  Batched requests currently remain a local-only operation. The Iris adapter
  accepts one request because the existing pipeline launches one cluster at a
  time.
  """
  @spec run_requests([String.t()]) :: {:ok, map()} | {:error, map()}
  @spec run_requests([String.t()], keyword()) :: {:ok, map()} | {:error, map()}
  def run_requests(request_paths, opts \\ [])

  def run_requests([], _opts) do
    {:error, %{reason: :no_verbalization_requests}}
  end

  def run_requests(request_paths, opts) when is_list(request_paths) do
    case Keyword.get(opts, :execution_backend, :local) do
      :local ->
        run_local_requests(request_paths, opts)

      :hpc_connect ->
        run_hpc_requests(request_paths, opts)

      backend ->
        {:error,
         %{
           reason: :unknown_verbalization_execution_backend,
           backend: backend
         }}
    end
  end

  defp run_local_requests(request_paths, opts) do
    project_root = Keyword.get_lazy(opts, :project_root, &File.cwd!/0)
    uv_executable = Keyword.get(opts, :uv_executable, "uv")

    arguments =
      [
        "run",
        "python",
        "-m",
        @python_module
      ] ++ Enum.map(request_paths, &Path.expand/1)

    case System.cmd(
           uv_executable,
           arguments,
           cd: project_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        decode_response(output)

      {output, exit_status} ->
        {:error,
         %{
           reason: :python_launcher_failed,
           exit_status: exit_status,
           output: output
         }}
    end
  rescue
    error in ErlangError ->
      {:error,
       %{
         reason: :python_process_failed,
         message: Exception.message(error)
       }}
  end

  defp run_hpc_requests([request_path], opts) do
    case VerbalHPCConnect.run_request(request_path, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, reason} ->
        {:error,
         %{
           reason: :hpc_verbalization_failed,
           detail: reason
         }}
    end
  end

  defp run_hpc_requests(request_paths, _opts) do
    {:error,
     %{
       reason: :hpc_verbalization_batch_not_supported,
       request_count: length(request_paths)
     }}
  end

  defp decode_response(output) do
    response =
      output
      |> String.split("\n", trim: true)
      |> Enum.reverse()
      |> Enum.find_value(fn line ->
        case Jason.decode(line) do
          {:ok, %{} = decoded} -> decoded
          _ -> nil
        end
      end)

    case response do
      nil ->
        {:error,
         %{
           reason: :invalid_python_response,
           output: output
         }}

      %{"status" => "completed"} = decoded ->
        {:ok, decoded}

      decoded ->
        {:error,
         %{
           reason: :verbalization_failed,
           response: decoded
         }}
    end
  end

  defp default_output_name(model_id) do
    model_id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
