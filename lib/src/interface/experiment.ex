defmodule Src.Interface.Experiment do
  @moduledoc """
  Connects Isabelle/Nitpick with the active countermodel pipeline.

  The experiment module orchestrates one complete countermodel run:

    1. execute an existing Isabelle theory,
    2. store the Isabelle/Nitpick output,
    3. parse the finite countermodel,
    4. generate a DOT/SVG visualization,
    5. generate the model-specific blocking axiom.

  Iteration over multiple countermodels is deliberately not handled here yet.
  """

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model
  alias Src.Core.Parser
  alias Src.Core.Render
  alias Src.Interface.Isabelle.Client

  @doc """
  Runs one existing Isabelle theory and prepares one visual countermodel entry.

  The theory must already contain the relevant Nitpick command.

  Important options:

    * `:iteration` - number of the current enumeration step, default `1`
    * `:base_theory_file` - unchanged legal/DDL base theory
    * `:output_dir` - directory for generated artifacts
    * `:relation` - relation parsed from Nitpick, default `"R"`
    * `:atoms` - unary predicates parsed from Nitpick
    * `:auto_atoms` - automatically detect unary predicates
    * `:axiom_option` - selected, externally provided DDL option
    * `:query` - the formula investigated by the theory
    * `:render_graph?` - render DOT to an image, default `true`
    * `:graph_format` - image format, default `"svg"`
    * `:highlight` - optional visualization highlight
    * `:include_atoms` - include valuations in the blocking axiom

  Isabelle-related options such as `:isabelle_bin`, `:threads`,
  `:session_name`, and `:write_root?` are forwarded to `Client`.
  """
  def analyse_theory(theory_path, opts \\ []) when is_binary(theory_path) do
    theory_path = Path.expand(theory_path)
    iteration = Keyword.get(opts, :iteration, 1)

    output_dir =
      opts
      |> Keyword.get(:output_dir, default_output_dir(theory_path, iteration))
      |> Path.expand()

    nitpick_output_file =
      Path.join(output_dir, "nitpick.txt")

    client_opts =
      Keyword.put(
        opts,
        :output_file,
        nitpick_output_file
      )

    with :ok <- ensure_output_dir(output_dir),
         {:ok, isabelle_run} <-
           Client.nitpick_theory(theory_path, client_opts),
         {:ok, model} <-
           safely_parse_nitpick_file(
             isabelle_run.output_file,
             opts
           ),
         {:ok, artifacts} <-
           write_countermodel_artifacts(
             model,
             isabelle_run,
             output_dir,
             iteration,
             opts
           ) do
      {:ok,
       %{
         status: :countermodel_found,

         iteration: iteration,

         base_theory_file:
           opts
           |> Keyword.get(:base_theory_file, theory_path)
           |> Path.expand(),

         search_theory_file: isabelle_run.theory_path,
         theory_name: isabelle_run.theory_name,

         axiom_option: Keyword.get(opts, :axiom_option),
         query: Keyword.get(opts, :query),

         nitpick_output_file: isabelle_run.output_file,

         model: model,
         model_summary: Model.as_summary(model),
         worlds: Model.world_indices(model),
         warnings: Model.warning_messages(model),

         graph_dot_file: artifacts.graph_dot_file,
         graph_image_file: artifacts.graph_image_file,

         blocking_axiom: artifacts.blocking_axiom,
         blocking_axiom_file: artifacts.blocking_axiom_file,

         highlight: Keyword.get(opts, :highlight),

         # Filled in during the later LLM phase.
         llm_explanation: nil,
         llm_metadata: nil,

         # Keep execution metadata, but not the complete duplicated log.
         isabelle_run:
           Map.drop(isabelle_run, [:log])
       }}
    end
  end

  @doc """
  Parses one previously stored Nitpick output and prepares its basic data.

  This keeps the older file-based workflow usable without invoking Isabelle.
  """
  def analyse_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    blocking_axiom =
      BlockingAxiom.blocking_axiom(
        model,
        name: Keyword.get(opts, :blocking_name),
        include_atoms: Keyword.get(opts, :include_atoms, true),
        include_initial: Keyword.get(opts, :include_initial, false),
        initial_world_constant: Keyword.get(opts, :initial_world_constant, "actual_world")
      )

    %{
      status: :parsed_countermodel,
      file: Path.expand(path),
      model: model,
      model_summary: Model.as_summary(model),
      worlds: Model.world_indices(model),
      warnings: Model.warning_messages(model),
      blocking_axiom: blocking_axiom,
      highlight: Keyword.get(opts, :highlight),
      llm_explanation: nil,
      llm_metadata: nil
    }
  end

  @doc """
  Returns a compact summary of one stored Nitpick output.
  """
  def summary_file(path, opts \\ []) do
    model = parse_nitpick_file(path, opts)

    model
    |> Model.as_summary()
    |> Map.merge(%{
      file: Path.expand(path),
      worlds: Model.world_indices(model),
      warning_count: length(model.warnings)
    })
  end

  @doc """
  Parses a stored Isabelle/Nitpick output.
  """
  def parse_nitpick_file(path, opts \\ []) do
    Parser.parse_nitpick_file(path,
      model_logic: Keyword.get(opts, :model_logic, :sdl),
      relation: Keyword.get(opts, :relation, "R"),
      atoms:
        opts
        |> Keyword.get(:atoms, [])
        |> normalize_atoms(),
      auto_atoms: Keyword.get(opts, :auto_atoms, false)
    )
  end

  defp write_countermodel_artifacts(model, isabelle_run, output_dir, iteration, opts) do
    try do
      graph_dot_file =
        Path.join(output_dir, "model.dot")

      Render.write_dot(
        model,
        graph_dot_file,
        atoms: Keyword.get(opts, :render_atoms),
        highlight: Keyword.get(opts, :highlight),
        palette: Keyword.get(opts, :palette, :turbo)
      )

      graph_image_file =
        maybe_render_graph(
          graph_dot_file,
          output_dir,
          opts
        )

      blocking_name =
        Keyword.get(
          opts,
          :blocking_name,
          "#{isabelle_run.theory_name}_model_#{iteration}"
        )

      blocking_axiom =
        BlockingAxiom.blocking_axiom(
          model,
          name: blocking_name,
          include_atoms: Keyword.get(opts, :include_atoms, true),
          include_initial: Keyword.get(opts, :include_initial, false),
          initial_world_constant:
            Keyword.get(
              opts,
              :initial_world_constant,
              "actual_world"
            )
        )

      blocking_axiom_file =
        Path.join(output_dir, "blocking_axiom.thyfrag")

      File.write!(
        blocking_axiom_file,
        blocking_axiom <> "\n"
      )

      {:ok,
       %{
         graph_dot_file: graph_dot_file,
         graph_image_file: graph_image_file,
         blocking_axiom: blocking_axiom,
         blocking_axiom_file: blocking_axiom_file
       }}
    rescue
      error in [File.Error, RuntimeError] ->
        {:error,
         {:artifact_generation_failed,
          %{
            output_dir: output_dir,
            message: Exception.message(error)
          }}}
    end
  end

  defp maybe_render_graph(dot_file, output_dir, opts) do
    if Keyword.get(opts, :render_graph?, true) do
      format =
        opts
        |> Keyword.get(:graph_format, "svg")
        |> to_string()

      output_file =
        Path.join(output_dir, "model.#{format}")

      Render.render_dot(dot_file,
        fmt: format,
        output_path: output_file
      )
    else
      nil
    end
  end

  defp safely_parse_nitpick_file(path, opts) do
    try do
      {:ok, parse_nitpick_file(path, opts)}
    rescue
      error in [ArgumentError, File.Error] ->
        {:error,
         {:nitpick_parse_failed,
          %{
            file: path,
            message: Exception.message(error)
          }}}
    end
  end

  defp ensure_output_dir(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
         {:cannot_create_output_directory,
          %{
            path: path,
            reason: reason
          }}}
    end
  end

  defp default_output_dir(theory_path, iteration) do
    theory_name =
      theory_path
      |> Path.basename(".thy")
      |> sanitize_path_part()

    iteration_name =
      iteration
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> then(&"iteration_#{&1}")

    Path.join([
      "out",
      theory_name,
      iteration_name
    ])
  end

  defp sanitize_path_part(value) do
    value
    |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
    |> String.trim("_")
  end

  defp normalize_atoms(nil), do: []
  defp normalize_atoms(""), do: []
  defp normalize_atoms("-"), do: []

  defp normalize_atoms(atoms) when is_binary(atoms) do
    atoms
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms) when is_list(atoms), do: atoms
end
