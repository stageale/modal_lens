defmodule Src.Interface.CLI do
  @moduledoc """
  Implements the ModalLens command-line interface.

  The CLI dispatches model enumeration, Nitpick summaries, blocking-axiom
  generation, and interactive demo generation.
  """
  alias Src.Core.BlockingAxiom
  alias Src.Enumeration
  alias Src.Execution.Options
  alias Src.Execution.Run
  alias Src.Explanation.Verbal.Launcher, as: VerbalLauncher
  alias Src.Interface.Ui
  alias Src.NitpickOutput
  alias Src.Refinement.Axiom
  alias Src.Refinement.Loop
  alias Src.Refinement.Report

  @demo_switches [
    relation: :string,
    atoms: :string,
    auto_atoms: :boolean,
    model_logic: :string,
    backend: :string,
    cardinality: :string,
    cardinality_feature: :boolean,
    feature_method: :string,
    graphlet_size: :integer,
    max_models: :integer,
    out_dir: :string,
    render_graph: :boolean,
    graph_format: :string,
    palette: :string,
    verbalize: :boolean,
    verbalization_model: :string,
    verbalization_mode: :string,
    verbalization_reasoning: :string,
    verbalization_max_new_tokens: :integer
  ]

  @common_switches [
    relation: :string,
    atoms: :string,
    auto_atoms: :boolean,
    strict: :boolean,
    model_logic: :string
  ]

  @enumeration_switches [
    input: :string,
    mode: :string,
    backend: :string,
    cardinality: :string,
    max_models: :integer,
    out_dir: :string,
    search_theory_dir: :string,
    isabelle_bin: :string,
    threads: :integer,
    include_atoms: :boolean,
    include_designated_world: :boolean
  ]

  @refinement_switches @demo_switches ++
                         [
                           max_refinement_rounds: :integer,
                           auto_refine: :boolean,
                           verbalization_backend: :string
                         ]

  @doc """
  Runs the command-line interface.

  Uses `System.argv/0` when no argument list is supplied.
  """
  @spec main() :: non_neg_integer() | :ok
  @spec main([String.t()]) :: non_neg_integer() | :ok
  def main(argv \\ System.argv()) do
    case argv do
      [] ->
        usage()

      ["help" | _] ->
        usage()

      ["enumerate" | rest] ->
        cmd_enumerate(rest)

      ["summary" | rest] ->
        cmd_summary(rest)

      ["axiom" | rest] ->
        cmd_axiom(rest)

      ["demo" | rest] ->
        cmd_demo(rest)

      ["refine" | rest] ->
        cmd_refine(rest)

      [unknown | _] ->
        IO.puts(:stderr, "[ERROR] Unknown command: #{unknown}")
        usage()
        1
    end
  end

  defp usage do
    IO.puts("""
    Usage:
      modal_lens demo INPUT.thy [-o DIR] [--palette turbo] [--graph-format svg] [--no-render-graph] [--no-verbalize]

      Not supported yet:
      modal_lens summary INPUTS... [--relation R] [--atoms go,tell] [--no-auto-atoms] [--json]
      modal_lens axiom   INPUTS... [--relation R] [--atoms go,tell] [--no-auto-atoms] [-o DIR] [--no-atoms]
      modal_lens enumerate INPUT.thy --mode MODE [options]

    Commands:
      enumerate   Enumerate countermodels or satisfying finite models.
      summary     Print compact summaries of Nitpick outputs.
      axiom       Generate Isabelle/HOL blocking axiom fragments.
      demo        Generate a small demo bundle with all outputs.

    Options:
      --input PATH                            Isabelle input theory.
                                              Default: lib/data/Input.thy

      --mode MODE                             countermodels,
                                              satisfying-models,
                                              consistency-check

      --no-verbalize                          Disable cluster and refinement verbalization.
                                              Verbalization is enabled by default.

      --no-render-graph                       Do not generate DOT, SVG, TikZ, or PDF graph files.

      --atoms LIST                            Include the named atoms explicitly.

      --no-auto-atoms                         Do not detect additional unary predicates.
                                              Automatic detection is enabled by default.

      --backend BACKEND                       Isabelle execution backend:
                                              local or hpc_connect.
                                              Default: local.

      --cardinality N|FIRST-LAST              World cardinality or inclusive range.
                                              Default: 2.

      --cardinality-feature                   Include world cardinality as an explicit
                                              graph-analysis feature.

      --verbalization-mode MODE               grounded or interpretive.
                                              Default: grounded.

      --verbalization-reasoning MODE          Extended model reasoning: on or off.
                                              Default: off.

      --verbalization-max-new-tokens N        Maximum generated tokens, including model reasoning.
                                              Default: 768.
    """)

    0
  end

  @spec cmd_refine([String.t()]) :: non_neg_integer()
  defp cmd_refine(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv, strict: @refinement_switches, aliases: [o: :out_dir])

    case {invalid, inputs} do
      {[], [theory_path]} ->
        option_set =
          [
            model_logic: :model_logic,
            backend: :backend,
            cardinality: :cardinality,
            cardinality_feature: :include_cardinality_feature?,
            feature_method: :feature_method,
            graphlet_size: :graphlet_size,
            relation: :relation,
            atoms: :atoms,
            auto_atoms: :auto_atoms?,
            max_models: :max_models,
            render_graph: :render_graph?,
            graph_format: :graph_format,
            palette: :palette,
            verbalize: :verbalize?,
            verbalization_backend: :verbalization_backend,
            verbalization_model: :verbalization_model,
            verbalization_mode: :verbalization_mode,
            verbalization_reasoning: :verbalization_reasoning?,
            verbalization_max_new_tokens: :verbalization_max_new_tokens
          ]
          |> Enum.reduce(%{}, fn {cli_key, option_key}, options ->
            case Keyword.fetch(opts, cli_key) do
              {:ok, value} -> Map.put(options, option_key, value)
              :error -> options
            end
          end)
          |> Map.update(:atoms, [], fn atoms ->
            atoms
            |> String.split(",", trim: true)
            |> Enum.map(&String.trim/1)
          end)

        output_dir = Keyword.get(opts, :out_dir, "out/refinement")
        max_rounds = Keyword.get(opts, :max_refinement_rounds, 1)

        decision =
          if Keyword.get(opts, :auto_refine, false) do
            :automatic
          else
            &confirm_refinement/3
          end

        with {:ok, options} <- Options.new(option_set),
             {:ok, run} <- Run.new("refinement", output_dir, Options.to_run_params(options)),
             {:ok, result} <-
               Loop.run(run, theory_path, max_rounds: max_rounds, decision: decision),
             {:ok, report_path} <- Report.write(result),
             {:ok, _session, page_path} <-
               Ui.write_refinement(result, result.initial_run.output_dir) do
          IO.puts("Refinement completed")
          IO.puts("Applied refinements: #{length(result.iterations)}")
          IO.puts("Stop reason: #{result.stop_reason}")
          IO.puts("Final theory: #{result.final_theory_path}")
          IO.puts("Final run directory: #{result.final_run.output_dir}")
          IO.puts("Refinement report: #{report_path}")
          IO.puts("UI: #{page_path}")

          maybe_verbalize_refinement(report_path, result.initial_run)
        else
          {:error, reason} ->
            IO.inspect(reason, label: "[ERROR] Refinement failed")

            1

          {:error, reason, _run} ->
            IO.inspect(reason, label: "[ERROR] Refinement failed")

            1
        end

      {[], []} ->
        IO.puts(:stderr, "[ERROR] Refine requires one .thy file.")
        2

      {[], _inputs} ->
        IO.puts(:stderr, "[ERROR] Refine accepts exactly one .thy file.")
        2

      {_invalid, _inputs} ->
        IO.puts(:stderr, "[ERROR] Invalid refinement options.")
        2
    end
  end

  @spec maybe_verbalize_refinement(String.t(), Run.t()) :: non_neg_integer()
  defp maybe_verbalize_refinement(report_path, %Run{} = run) do
    if Map.get(run.params, :verbalize?, false) do
      backend =
        Map.fetch!(run.params, :verbalization_backend)

      execution_backend =
        case backend do
          "ollama" -> :local
          _other -> Map.get(run.params, :backend, :local)
        end

      launcher_options = [
        execution_backend: execution_backend,
        output_name: ".",
        project_root: Map.get(run.params, :project_root, File.cwd!()),
        uv_executable: Map.get(run.params, :uv_executable, "uv"),
        seed: Map.get(run.params, :verbalization_seed, 42),
        max_new_tokens: Map.get(run.params, :verbalization_max_new_tokens, 768),
        backend_options: Map.get(run.params, :verbalization_backend_options, %{}),
        verbalization_mode: Map.get(run.params, :verbalization_mode, :grounded),
        reasoning: Map.get(run.params, :verbalization_reasoning?, false)
      ]

      case VerbalLauncher.launch(
             report_path,
             Path.join(run.output_dir, "verbalization/refinement"),
             backend,
             Map.fetch!(run.params, :verbalization_model),
             launcher_options
           ) do
        {:ok,
         %{
           request_path: request_path,
           response: %{"artifacts" => artifacts}
         }}
        when is_map(artifacts) ->
          IO.puts("Refinement verbalization completed.")
          IO.puts("Request: #{request_path}")

          Enum.each(Enum.sort(artifacts), fn {name, path} ->
            IO.puts("#{name}: #{path}")
          end)

          0

        {:error, reason} ->
          IO.inspect(reason, label: "[ERROR] Refinement verbalization failed")

          1

        {:ok, unexpected} ->
          IO.inspect(unexpected, label: "[ERROR] Invalid refinement verbalization response")

          1
      end
    else
      0
    end
  end

  @spec confirm_refinement(pos_integer(), Axiom.candidate(), map()) :: :apply | :stop
  defp confirm_refinement(round, candidate, _pipeline_result) do
    origin = candidate["origin"]

    IO.puts("\nRefinement candidate for round #{round}:")
    IO.puts("Candidate: #{candidate["candidate_id"]}")
    IO.puts("Cluster support: #{origin["cluster_support"]}")
    IO.puts("Outside support: #{origin["outside_support"]}")
    IO.puts("")
    IO.puts(Axiom.refinement_axiom(candidate))

    case IO.gets("\nApply this refinement axiom? [y/N] ") do
      answer when is_binary(answer) ->
        if String.downcase(String.trim(answer)) in ["y", "yes"] do
          :apply
        else
          :stop
        end

      _answer ->
        :stop
    end
  end

  defp cmd_enumerate(argv) do
    {opts, positional_args, invalid} =
      OptionParser.parse(
        argv,
        strict: @common_switches ++ @enumeration_switches,
        aliases: [
          o: :out_dir
        ]
      )

    with :ok <- reject_invalid_options(invalid),
         :ok <- reject_enumeration_positionals(positional_args),
         {:ok, mode} <- parse_enumeration_mode(Keyword.get(opts, :mode)),
         {:ok, model_logic} <- parse_model_logic(Keyword.get(opts, :model_logic, "sdl")),
         {:ok, backend} <- parse_backend(Keyword.get(opts, :backend, "local")),
         {:ok, cardinalities} <- parse_cardinalities(Keyword.get(opts, :cardinality, "2")) do
      input_path =
        Keyword.get(opts, :input)

      enumeration_opts =
        opts
        |> Keyword.drop([:input, :out_dir])
        |> Keyword.put(:mode, mode)
        |> Keyword.put(:model_logic, model_logic)
        |> Keyword.put(:backend, backend)
        |> Keyword.put(:cardinalities, cardinalities)
        |> maybe_put(:output_dir, Keyword.get(opts, :out_dir))

      enumeration_result =
        case input_path do
          nil -> Enumeration.enumerate(enumeration_opts)
          path -> Enumeration.enumerate(path, enumeration_opts)
        end

      case enumeration_result do
        {:ok, result} ->
          IO.puts("Enumeration completed.")
          IO.puts("Mode: #{mode}")
          IO.puts("Input: #{result.base_theory_file}")
          IO.puts("Status: #{inspect(result.status)}")
          IO.puts("Models found: #{result.model_count}")
          IO.puts("Output directory: #{result.output_dir}")

          0

        {:error, reason} ->
          IO.puts(:stderr, "[ERROR] Enumerationfailed:")
          IO.inspect(reason, pretty: true, limit: :infinity, printable_limit: :infinity)

          1
      end
    else
      {:error, message} ->
        IO.puts(:stderr, "[ERROR] #{message}")

        2
    end
  end

  defp parse_cardinalities(value) do
    case Options.new(cardinality: value) do
      {:ok, options} ->
        {:ok, options.cardinalities}

      {:error, {:invalid_cardinality, invalid}} ->
        {:error,
         "Invalid cardinality #{inspect(invalid)}." <>
           "Use a postive integer or inclusive range such as 2 or 2-4."}

      {:error, reason} ->
        {:error, "Invalid cardinality option: #{inspect(reason)}"}
    end
  end

  defp reject_enumeration_positionals([]), do: :ok

  defp reject_enumeration_positionals(positional_args) do
    {:error,
     "Unexpected positional arguments: " <>
       Enum.join(positional_args, " ") <> ". Use --input PATH to select another theory."}
  end

  defp parse_backend("local"), do: {:ok, :local}
  defp parse_backend("hpc_connect"), do: {:ok, :hpc_connect}
  defp parse_backend("hpc-connect"), do: {:ok, :hpc_connect}

  defp parse_backend(backend) do
    {:error, "Unknown backend #{inspect(backend)}. Use local or hpc_connect."}
  end

  defp parse_enumeration_mode("countermodels") do
    {:ok, :countermodels}
  end

  defp parse_enumeration_mode("consistency-check") do
    {:ok, :consistency_check}
  end

  defp parse_enumeration_mode("satisfying-models") do
    {:ok, :satisfying_models}
  end

  defp parse_enumeration_mode(nil) do
    {:error, "Missing --mode. Use countermodels, satisfying-models, or consistency-check."}
  end

  defp parse_enumeration_mode(mode) do
    {:error,
     "Unknown mode #{inspect(mode)}. Use countermodels, satisfying-models, or consistency-check."}
  end

  defp parse_model_logic("sdl"), do: {:ok, :sdl}
  defp parse_model_logic("ddl"), do: {:ok, :ddl}
  defp parse_model_logic("ed_stit"), do: {:ok, :ed_stit}
  defp parse_model_logic("ed-stit"), do: {:ok, :ed_stit}

  defp parse_model_logic(logic),
    do: {:error, "Unknown model logic #{inspect(logic)}. Use sdl, ddl or ed_stit."}

  defp maybe_put(opts, _key, nil) do
    opts
  end

  defp maybe_put(opts, key, value) do
    Keyword.put(opts, key, value)
  end

  defp cmd_summary(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv, strict: @common_switches ++ [json: :boolean])

    with :ok <- reject_invalid_options(invalid),
         :ok <- require_inputs(inputs),
         {:ok, model_logic} <- parse_model_logic(Keyword.get(opts, :model_logic, "sdl")),
         :ok <- ensure_json_available(opts) do
      opts = Keyword.put(opts, :model_logic, model_logic)

      inputs
      |> collect_input_files()
      |> Enum.each(fn file ->
        try do
          summary = NitpickOutput.summary_file(file, opts)

          if Keyword.get(opts, :json, false) do
            print_json(summary)
          else
            print_text_summary(summary)
          end

          print_warnings(file, summary.warnings)
        rescue
          exc ->
            IO.puts(:stderr, "[ERROR] #{file}: #{Exception.message(exc)}")
        end
      end)

      0
    else
      {:error, message} ->
        IO.puts(:stderr, "[ERROR] #{message}")
        1
    end
  end

  defp cmd_axiom(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv,
        strict:
          @common_switches ++
            [
              out_dir: :string,
              no_atoms: :boolean,
              include_designated_world: :boolean,
              designated_world_constant: :string
            ],
        aliases: [o: :out_dir]
      )

    with :ok <- reject_invalid_options(invalid),
         :ok <- require_inputs(inputs),
         {:ok, model_logic} <- parse_model_logic(Keyword.get(opts, :model_logic, "sdl")) do
      opts = Keyword.put(opts, :model_logic, model_logic)

      out_dir = Keyword.get(opts, :out_dir)
      include_atoms = not Keyword.get(opts, :no_atoms, false)

      if out_dir do
        File.mkdir_p!(out_dir)
      end

      inputs
      |> collect_input_files()
      |> Enum.each(fn file ->
        try do
          model = NitpickOutput.parse_nitpick_file(file, opts)

          blocking_opts =
            [
              include_atoms: include_atoms,
              include_designated_world: Keyword.get(opts, :include_designated_world, false)
            ]
            |> maybe_put(
              :designated_world_constant,
              Keyword.get(opts, :designated_world_constant)
            )

          axiom =
            BlockingAxiom.blocking_axiom(
              model,
              blocking_opts
            )

          if out_dir do
            out_path =
              file
              |> output_base(out_dir, "blocking_axiom")
              |> Kernel.<>(".thyfrag")

            File.write!(out_path, axiom <> "\n")
          end

          IO.puts("")
          IO.puts("(* #{file} *)")
          IO.puts(axiom)

          print_warnings(file, model.warnings)
        rescue
          exc ->
            IO.puts(:stderr, "[ERROR] #{file}: #{Exception.message(exc)}")
        end
      end)
    else
      {:error, message} ->
        IO.puts(:stderr, "[ERROR] #{message}")
        1
    end
  end

  defp cmd_demo(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv, strict: @demo_switches, aliases: [o: :out_dir])

    case {invalid, inputs} do
      {[], [theory_path]} ->
        option_set =
          [
            model_logic: :model_logic,
            backend: :backend,
            cardinality: :cardinality,
            cardinality_feature: :include_cardinality_feature?,
            feature_method: :feature_method,
            graphlet_size: :graphlet_size,
            relation: :relation,
            atoms: :atoms,
            auto_atoms: :auto_atoms?,
            max_models: :max_models,
            render_graph: :render_graph?,
            graph_format: :graph_format,
            palette: :palette,
            verbalize: :verbalize?,
            verbalization_model: :verbalization_model,
            verbalization_mode: :verbalization_mode,
            verbalization_reasoning: :verbalization_reasoning?,
            verbalization_max_new_tokens: :verbalization_max_new_tokens
          ]
          |> Enum.reduce(%{}, fn {cli_key, option_key}, options ->
            case Keyword.fetch(opts, cli_key) do
              {:ok, value} ->
                Map.put(options, option_key, value)

              :error ->
                options
            end
          end)
          |> Map.update(:atoms, [], fn atoms ->
            atoms
            |> String.split(",", trim: true)
            |> Enum.map(&String.trim/1)
          end)

        output_dir = Keyword.get(opts, :out_dir, "out/demo")

        case Ui.run(theory_path, output_dir, [option_set]) do
          {:ok, _session, page_path} ->
            IO.puts("Demo completed.")
            IO.puts("HTML: #{page_path}")
            0

          {:error, reason} ->
            IO.inspect(reason, label: "[ERROR] Demo failed")
            1

          {:error, reason, _run} ->
            IO.inspect(reason, label: "[ERROR] Demo failed")
            1
        end

      {[], []} ->
        IO.puts(:stderr, "[ERROR] Demo requires one .thy file.")
        2

      {[], _inputs} ->
        IO.puts(:stderr, "[ERROR] Demo accepts exactly one .thy file.")
        2

      {_invalid, _inputs} ->
        IO.puts(:stderr, "[ERROR] Invalid demo options.")
        2
    end
  end

  defp collect_input_files(paths) do
    paths
    |> Enum.flat_map(fn raw ->
      cond do
        File.dir?(raw) ->
          raw
          |> Path.join("*.txt")
          |> Path.wildcard()
          |> Enum.sort()

        true ->
          [raw]
      end
    end)
  end

  defp print_text_summary(summary) do
    IO.puts(format_summary(summary))
  end

  defp format_summary(%{model_logic: :ed_stit} = summary) do
    "modalities=#{summary.modality_count}, " <>
      "accessibility=#{summary.accessibility_count}, " <>
      "agents=#{inspect(summary.agents)}, " <>
      "atoms=#{inspect(summary.atoms)}"
  end

  defp format_summary(summary) do
    "relation=#{summary.relation}, " <>
      "edges=#{summary.edge_count}, " <>
      "atoms=#{inspect(summary.atoms)}"
  end

  defp print_warnings(file, warnings) do
    Enum.each(warnings, fn warning ->
      IO.puts("  [WARNING] #{file}: #{warning_message(warning)}")
    end)
  end

  defp warning_message(warning) when is_binary(warning), do: warning
  defp warning_message(%{message: message}), do: message
  defp warning_message(warning), do: inspect(warning)

  defp output_base(file, out_dir, prefix) do
    ext = Path.extname(file)
    stem = Path.basename(file, ext)
    Path.join(out_dir, "#{prefix}_#{stem}")
  end

  defp reject_invalid_options([]), do: :ok

  defp reject_invalid_options(invalid) do
    rendered =
      invalid
      |> Enum.map(fn {option, value} -> "#{option} #{value}" end)
      |> Enum.join(", ")

    {:error, "Invalid option(s): #{rendered}"}
  end

  defp require_inputs([]), do: {:error, "No input files given."}
  defp require_inputs(_inputs), do: :ok

  defp ensure_json_available(opts) do
    if Keyword.get(opts, :json, false) do
      case Code.ensure_loaded(Jason) do
        {:module, _} ->
          :ok

        _ ->
          {:error, "--json requires Jason. Add {:jason, \"~> 1.4\"} to deps or omit --json."}
      end
    else
      :ok
    end
  end

  defp print_json(value) do
    IO.puts(apply(Jason, :encode!, [value, [pretty: true]]))
  end
end
