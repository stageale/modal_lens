defmodule Src.Isabelle.Client do
  @moduledoc """
  High-level entry point for Isabelle-based reasoning.

  The client supports two kinds of Isabelle runs:

  1. Generated HOL embeddings represented by `HOLEmbedding`.
  2. Existing Isabelle theory files, for example DDL case studies.

  In both cases, the Isabelle build log is written to a text file that can
  subsequently be consumed by the existing Nitpick parser.
  """

  alias Src.Isabelle.HOLEmbedding
  alias Src.Isabelle.LocalConnect
  alias Src.Isabelle.HPCConnect

  @doc """
  Generates an Isabelle theory from a `HOLEmbedding`, runs Nitpick and stores
  the Isabelle build log.

  This preserves the existing API.
  """
  @spec nitpick_countermodel(%HOLEmbedding{}) ::
        {:ok, map()} | {:error, term()}
  @spec nitpick_countermodel(%HOLEmbedding{}, keyword()) ::
        {:ok, map()} | {:error, term()}
  def nitpick_countermodel(%HOLEmbedding{} = spec, opts \\ []) do
    reason_generated_theory(spec, opts)
  end

  @doc """
  Runs an existing Isabelle theory file.

  The theory is expected to already contain the relevant Nitpick command,
  for example:

      lemma target:
        "some_formula"
        nitpick [user_axioms]
        oops

  By default, the directory containing the theory is used as Isabelle
  session directory. If no `ROOT` file exists, a minimal one is generated.

  Options:

    * `:backend` - currently `:local` or `:hpc_connect`
    * `:workdir` - Isabelle session directory
    * `:session_name` - session name used in `ROOT`
    * `:output_file` - path for the captured Isabelle log
    * `:write_root?` - whether a missing `ROOT` should be generated
    * all options understood by `LocalConnect`
  """
  @spec nitpick_theory(Path.t()) ::
        {:ok, map()} | {:error, term()}

  @spec nitpick_theory(Path.t(), keyword()) ::
        {:ok, map()} | {:error, term()}

  def nitpick_theory(theory_path, opts \\ []) when is_binary(theory_path) do
    theory_path = Path.expand(theory_path)

    with :ok <- validate_theory_file(theory_path),
         {:ok, theory_name} <- read_theory_name(theory_path) do
      workdir =
        opts
        |> Keyword.get(:workdir, Path.dirname(theory_path))
        |> Path.expand()

      session_name = Keyword.get(opts, :session_name, theory_name)

      output_file =
        opts
        |> Keyword.get(
          :output_file,
          Path.join(workdir, "#{theory_name}.nitpick.txt")
        )
        |> Path.expand()

      logic = Keyword.get(opts, :logic, "HOL")

      backend_opts =
        Keyword.put(opts, :theory_path, theory_path)

      with  :ok <- ensure_theory_in_workdir(theory_path, workdir),
            :ok <- ensure_root(workdir, theory_name, session_name, logic, opts),
           {:ok, result} <- run_backend(workdir, theory_name, backend_opts),
            :ok <- write_log(output_file, result.log) do
        {:ok,
         %{
           theory_name: theory_name,
           theory_path: theory_path,
           session_name: session_name,
           logic: logic,
           workdir: workdir,
           output_file: output_file,
           build_output: result.build_output,
           log: result.log,
           backend: Keyword.get(opts, :backend, :local)
         }}
      end
    end
  end

  defp reason_generated_theory(%HOLEmbedding{} = spec, opts) do
    backend = Keyword.get(opts, :backend, :local)
    workdir = Keyword.get(opts, :workdir, default_workdir())

    output_file =
      Keyword.get(
        opts,
        :output_file,
        Path.join(workdir, "nitpick-output.txt")
      )

    HOLEmbedding.write_root!(spec, workdir)
    HOLEmbedding.write_theory!(spec, workdir)

    with {:ok, result} <- run_backend(workdir, spec.theory_name, opts),
         :ok <- write_log(output_file, result.log) do
      {:ok,
       %{
         theory_name: spec.theory_name,
         theory_path: Path.join(workdir, "#{spec.theory_name}.thy"),
         session_name: spec.theory_name,
         output_file: output_file,
         workdir: workdir,
         build_output: result.build_output,
         log: result.log,
         backend: backend
       }}
    end
  end

  defp run_backend(workdir, theory_name, opts) do
    #session_name = Keyword.get(opts, :session_name, theory_name)
    case Keyword.get(opts, :backend, :local) do
      :local ->
        base_theory_path =
          Keyword.get(opts, :base_theory_file)

        theory_paths =
          local_import_files(base_theory_path) ++ [Keyword.get(opts, :base_theory_file), Keyword.fetch!(opts, :theory_path)]
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&Path.expand/1)
          |> Enum.uniq()

        with {:ok, log} <- LocalConnect.process_theories(theory_paths, opts) do
                {:ok,
                  %{
                    build_output: nil,
                    log: log
                  }}
               end

      :hpc_connect ->
        with {:ok, log} <- HPCConnect.run(workdir, %{theory_name: theory_name}, opts) do
          {:ok,
            %{
              build_output: nil,
              log: log
            }
          }
        end

      other ->
        {:error, {:unknown_backend, other}}
    end
  end

  defp ensure_root(workdir, theory_name, session_name, logic, opts) do
    root_path = Path.join(workdir, "ROOT")

    session_source = """
    session #{session_name} = #{logic} +
      theories
        #{theory_name}
    """

    cond do
      File.regular?(root_path) ->
        with {:ok, source} <- File.read(root_path) do
          session_pattern = ~r/!\s*session\s+#{Regex.escape(session_name)}\s*=/m

          if Regex.match?(session_pattern, source) do
            :ok
          else
            File.write(root_path, String.trim_trailing(source) <> "\n\n" <> session_source)
          end
        end
      Keyword.get(opts, :write_root?, true) -> File.write(root_path, session_source)
      true -> {:error, {:missing_root, root_path}}
    end
  end

  defp validate_theory_file(path) do
    cond do
      not File.exists?(path) -> {:error, {:theory_not_found, path}}
      not File.regular?(path) -> {:error, {:not_a_regular_file, path}}
      Path.extname(path) != ".thy" -> {:error, {:not_an_isabelle_theory, path}}
      true -> :ok
    end
  end

  defp read_theory_name(path) do
    case File.read(path) do
      {:ok, source} ->
        case Regex.run(
               ~r/^\s*theory\s+([A-Za-z0-9_'.]+)/m,
               source,
               capture: :all_but_first
             ) do
          [theory_name] ->
            {:ok, theory_name}

          nil ->
            {:error, {:missing_theory_declaration, path}}
        end

      {:error, reason} ->
        {:error, {:cannot_read_theory, path, reason}}
    end
  end

  defp ensure_theory_in_workdir(theory_path, workdir) do
    theory_dir =
      theory_path
      |> Path.dirname()
      |> Path.expand()

    if theory_dir == workdir do
      :ok
    else
      {:error,
       {:theory_outside_workdir,
        %{
          theory_path: theory_path,
          workdir: workdir,
          hint:
            "For the first implementation, use the directory containing the theory as workdir."
        }}}
    end
  end

  defp write_log(output_file, log) when is_binary(log) do
    output_file
    |> Path.dirname()
    |> File.mkdir_p!()

    case File.write(output_file, log) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error, {:cannot_write_isabelle_log, output_file, reason}}
    end
  end

  defp local_import_files(nil), do: []

  defp local_import_files(theory_path) do
    with {:ok, source} <- File.read(theory_path),
        [imports] <- Regex.run(~r/\bimports\s+(.*?)\bbegin\b/s, source, capture: :all_but_first) do
          imports
          |> String.replace(~r/\(\*.*?\*\)/s, " ")
          |> String.replace("\"", "")
          |> String.split()
          |> Enum.map(fn import_name ->
            filename =
              if Path.extname(import_name) == ".thy" do
                import_name
              else
                import_name <> ".thy"
              end
            Path.expand(filename, Path.dirname(theory_path))
          end)
          |> Enum.filter(&File.regular?/1)
        else
          _ -> []
        end
  end

  defp default_workdir do
    Path.join(["tmp", "isabelle", timestamp()])
  end

  defp timestamp do
    DateTime.utc_now()
    |> DateTime.to_iso8601(:basic)
    |> String.replace(~r/[^0-9A-Za-z]/, "_")
  end
end
