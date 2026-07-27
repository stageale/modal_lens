defmodule Src.Interface.Common.ArtifactStore do
  @moduledoc """
  Persists run manifests and manages files belonging to one run.

  Artifact paths are stored relative to the run output directory.
  """

  alias Src.Interface.Common.Run

  @manifest_filename "run.json"

  @type artifact_name :: atom() | String.t()


  @doc """
  Creates the output directory of a run.
  """
  @spec prepare(Run.t()) :: {:ok, Run.t()} | {:error, term()}
  def prepare(%Run{} = run) do
    case File.mkdir_p(run.output_dir) do
      :ok -> {:ok, run}
      {:error, reason} ->
        {:error,
          {
            :cannot_create_output_directory,
            run.output_dir,
            reason
          }
        }
    end
  end

  @doc """
  Writes deterministic JSON and registers it as an artifact.
  """
  @spec write_json(Run.t(), artifact_name(), String.t(), term()) :: {:ok, Run.t(), String.t()} | {:error, term()}
  def write_json(%Run{} = run, name, relative_path, value) do
    case Jason.encode(value, pretty: true) do
      {:ok, json} -> write_artifact(run, name, relative_path, json <> "\n")
      {:error, reason} -> {:error, {:json_encoding_failed, reason}}
    end
  end

  @doc """
  Writes text and registers it as an artifact.
  """
  @spec write_text(Run.t(), artifact_name(), String.t(), binary()) :: {:ok, Run.t(), String.t()} | {:error, term()}
  def write_text(%Run{} = run, name, relative_path, content) do
    if is_binary(content) do
      write_artifact(run, name, relative_path, content)
    else
      {:error, {:invalid_artifact_content, name}}
    end
  end

  @doc """
  Registers an existing regular file belonging to the run.
  """
  @spec register(Run.t(), artifact_name(), String.t()) :: {:ok, Run.t(), String.t()} | {:error, term()}
  def register(%Run{} = run, name, path) when is_binary(path) do
    with {:ok, absolute_path, relative_path} <- resolve_path(run, path),
         true <- File.regular?(absolute_path),
         {:ok, updated_run} <- Run.put_artifact(run, name, relative_path) do
           {:ok, updated_run, absolute_path}
    else
      false -> {:error, {:artifact_not_found, path}}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Writes the current run state to `run.json`.
  """
  @spec persist(Run.t()) :: {:ok, String.t()} | {:error, term()}
  def persist(%Run{} = run) do
    path = manifest_path(run)

    with {:ok, _run} <- prepare(run),
         {:ok, json} <- Jason.encode(Run.to_map(run), pretty: true),
          :ok <- File.write(path, json <> "\n") do
            {:ok, path}
    else
      {:error, %Jason.EncodeError{} = reason} -> {:error, {:json_encoding_failed, reason}}
      {:error, reason} -> {:error, {:cannot_persist_run, path, reason}}
    end
  end

  @doc """
  Returns the absolute path of a run manifest.
  """
  @spec manifest_path(Run.t() | String.t()) :: String.t()
  def manifest_path(%Run{} = run) do
    manifest_path(run.output_dir)
  end

  def manifest_path(output_dir) when is_binary(output_dir) do
    output_dir
    |> Path.expand()
    |> Path.join(@manifest_filename)
  end

  @doc """
  Reads and decodes a stored run manifest.
  """
  @spec read_manifest(Run.t() | String.t()) :: {:ok, map()} | {:error, term()}
  def read_manifest(%Run{} = run) do
    read_manifest(run.output_dir)
  end

  def read_manifest(output_dir) when is_binary(output_dir) do
    path = manifest_path(output_dir)
    with {:ok, content} <- File.read(path),
         {:ok, manifest} <- Jason.decode(content) do
           {:ok, manifest}
    else
      {:error, %Jason.DecodeError{} = reason} -> {:error, {:invalid_manifest, path, reason}}
      {:error, reason} -> {:error, {:cannot_read_manifest, path, reason}}
    end
  end

  def read_manifest(value) do
    {:error, {:invalid_output_directory, value}}
  end

  @doc """
  Resolves the absolute path of a registered artifact.
  """
  @spec artifact_path(Run.t(), artifact_name()) :: {:ok, String.t()} | {:error, term()}
  def artifact_path(%Run{} = run, name) do
    name =
      if is_atom(name) do
        Atom.to_string(name)
      else
        name
      end

    case Map.fetch(run.artifacts, name) do
      {:ok, relative_path} ->
        case resolve_path(run, relative_path) do
          {:ok, absolute_path, _relative_path} -> {:ok, absolute_path}
          {:error, _reason} = error -> error
        end

      :error -> {:error, {:unknown_artifact, name}}
    end
  end

  defp write_artifact(%Run{} = run, name, relative_path, content) do
    with {:ok, _run} <- prepare(run),
         {:ok, absolute_path, relative_path} <- resolve_path(run, relative_path),
         :ok <- File.mkdir_p(Path.dirname(absolute_path)),
         :ok <- File.write(absolute_path, content),
         {:ok, updated_run} <- Run.put_artifact(run, name, relative_path) do
      {:ok, updated_run, absolute_path}
    else
      {:error, reason} ->
        {:error,
          {:cannot_write_artifact,
            relative_path,
            reason
          }
        }
    end
  end

  defp resolve_path(%Run{} = run, path) when is_binary(path) do
    output_dir = Path.expand(run.output_dir)
    absolute_path = Path.expand(path, output_dir)
    relative_path = Path.relative_to(absolute_path, output_dir)

    if relative_path == ".." or
         String.starts_with?(relative_path, "../") do
      {:error, {:artifact_outside_output_directory, path}}
    else
      {:ok, absolute_path, relative_path}
    end
  end

  defp resolve_path(%Run{}, path) do
    {:error, {:invalid_artifact_path, path}}
  end
end
