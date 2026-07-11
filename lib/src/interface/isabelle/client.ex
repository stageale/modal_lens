defmodule Src.Interface.Isabelle.Client do
  @moduledoc """
  High-level entry point for Isabelle-based reasoning.

  The client supports two kinds of Isabelle runs:

  1. Generated HOL embeddings represented by `HOLEmbedding`.
  2. Existing Isabelle theory files, for example DDL case studies.

  In both cases, the Isabelle build log is written to a text file that can
  subsequently be consumed by the existing Nitpick parser.
  """

  alias Src.Interface.Isabelle.HOLEmbedding
  alias Src.Interface.Isabelle.LocalConnect
  #alias Src.Interface.Isabelle.HPCConnect

  @doc """
  Generates an Isabelle theory from a `HOLEmbedding`, runs Nitpick and stores
  the Isabelle build log.

  This preserves the existing API.
  """
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
  def nitpick_theory(theory_path, opts \\ []) when is_binary(theory_path) do
    theory_path = Path.expand(theory_path)

    with :ok <- validate_theory_file(theory_path),
         {:ok, theory_name} <- read_theory_name(theory_path) do
      workdir =
        opts
        |> Keyword.get(:workdir, Path.dirname(theory_path))
        |> Path.expand()

      session_name =
        Keyword.get(
          opts,
          :session_name,
          default_session_name(theory_name)
        )

      output_file =
        opts
        |> Keyword.get(
          :output_file,
          Path.join(workdir, "#{theory_name}.nitpick.txt")
        )
        |> Path.expand()

      write_root? = Keyword.get(opts, :write_root?, true)

      with :ok <- ensure_theory_in_workdir(theory_path, workdir),
           :ok <- maybe_write_root(workdir, session_name, theory_name, write_root?),
           {:ok, log} <- run_backend(workdir, session_name, opts),
           :ok <- write_log(output_file, log) do
        {:ok,
         %{
           theory_name: theory_name,
           theory_path: theory_path,
           session_name: session_name,
           workdir: workdir,
           output_file: output_file,
           log: log,
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

    with {:ok, log} <- run_backend(workdir, spec.theory_name, opts),
         :ok <- write_log(output_file, log) do
      {:ok,
       %{
         theory_name: spec.theory_name,
         theory_path: Path.join(workdir, "#{spec.theory_name}.thy"),
         session_name: spec.theory_name,
         output_file: output_file,
         workdir: workdir,
         log: log,
         backend: backend
       }}
    end
  end

  defp run_backend(workdir, session_name, opts) do
    case Keyword.get(opts, :backend, :local) do
      :local ->
        LocalConnect.build(
          workdir,
          %{theory_name: session_name},
          opts
        )

      :hpc_connect ->
        {:error,
         {:unsupported_existing_theory_backend,
          "Existing theory execution through HPCConnect is not connected yet."}}

      other ->
        {:error, {:unknown_backend, other}}
    end
  end

  defp validate_theory_file(path) do
    cond do
      not File.exists?(path) ->
        {:error, {:theory_not_found, path}}

      not File.regular?(path) ->
        {:error, {:not_a_regular_file, path}}

      Path.extname(path) != ".thy" ->
        {:error, {:not_an_isabelle_theory, path}}

      true ->
        :ok
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

  defp maybe_write_root(_workdir, _session_name, _theory_name, false) do
    :ok
  end

  defp maybe_write_root(workdir, session_name, theory_name, true) do
    root_path = Path.join(workdir, "ROOT")

    if File.exists?(root_path) do
      :ok
    else
      File.mkdir_p!(workdir)

      root_source = """
      session #{session_name} = HOL +
        theories
          #{theory_name}
      """

      case File.write(root_path, root_source) do
        :ok ->
          :ok

        {:error, reason} ->
          {:error, {:cannot_write_root, root_path, reason}}
      end
    end
  end

  defp write_log(output_file, log) do
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

  defp default_session_name(theory_name) do
    "Axiom_Refiner_#{theory_name}"
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