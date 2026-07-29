defmodule Src.Interface.CLI do
  alias Src.Interface.Experiment
  alias Src.Core.BlockingAxiom
  alias Src.ModelEnumeration
  alias Src.Interface.Ui

  @demo_switches [
    relation: :string,
    atoms: :string,
    auto_atoms: :boolean,
    model_logic: :string,
    out_dir: :string,
    graph_format: :string,
    palette: :string,
    verbalize: :boolean,
    verbalization_model: :string
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
    max_models: :integer,
    out_dir: :string,
    search_theory_dir: :string,
    isabelle_bin: :string,
    threads: :integer,
    include_atoms: :boolean,
    include_designated_world: :boolean
  ]

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

      ["rank" | rest] ->
        cmd_rank(rest)

      ["demo" | rest] ->
        cmd_demo(rest)

      # ["graphviz" | _rest] ->
      #  not_implemented("tikz")
      [unknown | _] ->
        IO.puts(:stderr, "[ERROR] Unknown command: #{unknown}")
        usage()
        1
    end
  end

  defp usage do
    IO.puts("""
    Usage:
      axiom_refiner demo INPUT.thy [-o DIR] [--palette turbo] [--graph-format svg] [--verbalize]

      Not supported yet:
      axiom_refiner summary INPUTS... [--relation R] [--atoms go,tell] [--auto-atoms] [--json]
      axiom_refiner axiom   INPUTS... [--relation R] [--atoms go,tell] [--auto-atoms] [-o DIR] [--no-atoms]
      axiom_refiner enumerate INPUT.thy --mode MODE [options]

    Commands:
      enumerate   Enumerate countermodelsor satisfying finite models.
      summary     Print compact summaries of Nitpick outputs.
      axiom       Generate Isabelle/HOL blocking axiom fragments.
      rank        Rank multiple Nitpick outputs by simple model features.
      demo        Generate a small demo bundle with all outputs outputs.

    Options:
      --input PATH      Isabelle input theory.
                        Default: lib/data/Input.thy

      --mode MODE       countermodels,
                        satisfying-models,
                        consistency-check
    """)

    0
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
        {:ok, model_logic} <- parse_model_logic(Keyword.get(opts, :model_logic, "sdl")) do
          input_path =
            Keyword.get(opts, :input)

          enumeration_opts =
            opts
            |> Keyword.drop([:input, :out_dir])
            |> Keyword.put(:mode, mode)
            |> Keyword.put(:model_logic, model_logic)
            |> maybe_put(:output_dir, Keyword.get(opts, :out_dir))

          enumeration_result =
            case input_path do
              nil -> ModelEnumeration.enumerate(enumeration_opts)
              path -> ModelEnumeration.enumerate(path, enumeration_opts)
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

  defp reject_enumeration_positionals([]), do: :ok

  defp reject_enumeration_positionals(positional_args) do
    {:error, "Unexpected positional arguments: " <> Enum.join(positional_args, " ") <> ". Use --input PATH to select another theory."}
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
    {:error, "Unknown mode #{inspect(mode)}. Use countermodels, satisfying-models, or consistency-check."}
  end

  defp parse_model_logic("sdl"), do: {:ok, :sdl}
  defp parse_model_logic("ddl"), do: {:ok, :ddl}
  defp parse_model_logic(logic), do: {:error, "Unknown model logic #{inspect(logic)}. Use sdl or ddl."}

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
          summary = Experiment.summary_file(file, opts)

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
        strict: @common_switches ++ [out_dir: :string, no_atoms: :boolean, include_designated_world: :boolean, designated_world_constant: :string],
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
          model = Experiment.parse_nitpick_file(file, opts)

          blocking_opts =
            [
              includ_atoms: include_atoms,
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

  defp cmd_rank(_argv) do
    IO.puts(
      :stderr,
      "[ERROR] The rank command belongs to the deprecated axiom-scoring pipeline."
    )

    1
  end

  defp cmd_demo(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv, strict: @demo_switches, aliases: [o: :out_dir])

    case {invalid, inputs} do
      {[], [theory_path]} ->
        model_logic =
          case Keyword.get(opts, :model_logic, "sdl") do
            "sdl" -> :sdl
            "ddl" -> :ddl
            value ->
              IO.puts(:stderr, "[ERROR] Unsupported model logic: #{value}")
              nil
          end

        if model_logic do
          option_set = %{
            model_logic: model_logic,
            relation: Keyword.get(opts, :relation, "R"),
            atoms:
              opts
              |> Keyword.get(:atoms, "")
              |> String.split(",", trim: true)
              |> Enum.map(&String.trim/1),
            auto_atoms?: Keyword.get(opts, :auto_atoms, true),
            render_graph?: true,
            graph_format:
              opts
              |> Keyword.get(:graph_format, "svg")
              |> String.to_atom(),
            palette:
              opts
              |> Keyword.get(:palette, "turbo")
              |> String.to_atom(),
            verbalize?: Keyword.get(opts, :verbalize, false),
            verbalization_model:
              Keyword.get(opts, :verbalization_model, "HuggingFaceTB/SmolLM3-3B")
          }

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
        else
          2
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
    IO.puts(
      "#{summary.source}: #{summary.kind}, card=#{summary.cardinality}, " <>
        "relation=#{summary.relation}, edges=#{summary.edge_count}, atoms=#{inspect(summary.atoms)}"
    )
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
