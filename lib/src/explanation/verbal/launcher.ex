defmodule Src.Explanation.Verbal.Launcher do
  @moduledoc """
  Creates and launches Python verbalization jobs.
  """

  alias Src.Explanation.Verbal.Job

  @python_module "verbalization.launcher"

  def launch(report_path, output_root, backend, model_id, opts \\ []) do
    output_name = Keyword.get_lazy(opts, :output_name, fn -> default_output_name(model_id) end)
    output_directory = Path.join(output_root, output_name)
    job_options = Keyword.take(opts, [:seed, :max_new_tokens, :backend_options])

    with  {:ok, job} <- Job.new(backend, model_id, report_path, output_directory, job_options),
           request_path <- Job.build_request_path(output_directory),
          {:ok, request_path} <- Job.write(job, request_path),
          {:ok, response} <- run_request(request_path, opts) do
            {:ok,
              %{
                job: job,
                request_path: request_path,
                response: response
              }
            }
          end
  end

  def launch_async(report_path, output_root, backend, model_id, opts \\ []) do
    Task.async(fn -> launch(report_path, output_root, backend, model_id, opts) end)
  end

  def run_request(request_path, opts \\ []) do
    project_root = Keyword.get_lazy(opts, :project_root, &File.cwd!/0)
    uv_executable = Keyword.get(opts, :uv_executable, "uv")
    arguments = ["run", "python", "-m", @python_module, Path.expand(request_path)]

    case System.cmd(
      uv_executable,
      arguments,
      cd: project_root,
      stderr_to_stdout: true
    ) do
      {output, 0} -> decode_response(output)
      {output, exit_status} ->
        {:error,
          %{
            reason: :python_launcher_failed,
            exit_status: exit_status,
            output: output
          }
        }
    end
    rescue
      error in ErlangError ->
        {:error,
          %{
            reason: :python_process_failed,
            message: Exception.message(error)
          }
        }
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
          }
        }

      %{"status" => "completed"} = decoded ->
        {:ok, decoded}

      decoded ->
        {:error,
          %{
            reason: :verbalization_failed,
            response: decoded
          }
        }
    end
  end

  defp default_output_name(model_id) do
    model_id
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
  end
end
