defmodule Src.Interface.CLI do
  alias Src.Core.Parser

  @common_switches [
    relation: :string,
    atoms: :string,
    auto_atoms: :boolean,
    strict: :boolean
  ]

  def main(argv \\ System.argv()) do
    case argv do
      [] ->
        usage()
      ["help" | _] ->
        usage()
      ["summary" | rest] ->
        cmd_summary(rest)
      ["axiom" | rest] ->
        cmd_axiom(rest)
      ["graphviz" | _rest] ->
        not_implemented("tikz")
      [unknown | _] ->
        IO.puts(:stderr, "[ERROR] Unknown command: #{unknown}")
        usage()
        1
    end
  end

  defp usage do
    IO.puts("""
    Usage:
      axiom_refiner summary INPUTS... [--relation R] [--atoms go,tell] [--auto-atoms] [--json]
      axiom_refiner axiom   INPUTS... [--relation R] [--atoms go,tell] [--auto-atoms] [-o DIR] [--no-atoms]

    Commands:
      summary   Print compact summaries of Nitpick outputs.
      axiom     Generate Isabelle/HOL blocking axiom fragments.
      graphviz  Not ported yet.
      tikz      Not ported yet.
    """)

    0
  end

  defp not_implemented(command) do
    IO.puts(:stderr, "[ERROR] Command '#{command}' is not implemented yet.")
    1
  end

  defp cmd_summary(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv, strict: @common_switches ++ [json: :boolean])

    with :ok <- reject_invalid_options(invalid),
         :ok <- require_inputs(inputs),
         :ok <- ensure_json_available(opts) do
          inputs
          |> collect_input_files()
          |> run_for_files(opts, fn file, model ->
            summary = model_summary(model)

            if Keyword.get(opts, :json, false) do
              print_json(summary)
            else
              print_text_summary(summary)
            end

            print_warnings(file, model.warnings)
          end)
        else
          {:error, message} ->
            IO.puts(:stderr, "[ERROR] #{message}")
            1
        end
  end

  defp cmd_axiom(argv) do
    {opts, inputs, invalid} =
      OptionParser.parse(argv,
        strict: @common_switches ++ [out_dir: :string, no_atoms: :boolean],
        aliases: [o: :out_dir]
      )
    with :ok <- reject_invalid_options(invalid),
         :ok <- require_inputs(inputs) do
      out_dir = Keyword.get(opts, :out_dir)

      if out_dir do
        File.mkdir_p!(out_dir)
      end

      inputs
      |> collect_input_files()
      |> run_for_files(opts, fn file, model ->
        include_atoms = not Keyword.get(opts, :no_atoms, false)
        axiom = blocking_axiom(model, include_atoms)

        if out_dir do
          out_path =
            file
            |> output_base(out_dir, "blocking_axiom")
            |> Kernel.<>(".thyfrag")

          File.write!(out_path, axiom <> "\n")
          IO.puts("")
          IO.puts("(* #{file} *)")
          IO.puts(axiom)
        end

        print_warnings(file, model.warnings)
      end)
    else
      {:error, message} ->
        IO.puts(:stderr, "[ERROR] #{message}")
        1
    end
  end

  defp run_for_files(files, opts, fun) do
    Enum.reduce_while(files, 0, fn file, status ->
      try do
        model = parse_model(file, opts)
        fun.(file, model)
        {:cont, status}
      rescue
        exc ->
          IO.puts(:stderr, "[ERROR] #{file}: #{Exception.message(exc)}")

          if Keyword.get(opts, :strict, false) do
            {:halt, 1}
          else
            {:cont, status}
          end
      end
    end)
  end

  defp parse_model(file, opts) do
    Parser.parse_nitpick_file(file,
      relation: Keyword.get(opts, :relation, "R"),
      atoms: parse_atoms(Keyword.get(opts, :atoms)),
      auto_atoms: Keyword.get(opts, :auto_atoms, false)
    )
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

  defp parse_atoms(nil), do: []
  defp parse_atoms(""), do: []
  defp parse_atoms("-"), do: []

  defp parse_atoms(raw) do
    raw
    |> String.split(",")
    |> Enum.map(fn x -> String.trim(x) end)
    |> Enum.reject(fn x -> x == "" end)
  end

  defp model_summary(model) do
    %{
      source: model.source || "<text>",
      kind: model.kind,
      cardinality: model.cardinality,
      relation: model.relation_name,
      initial_world: world_name(model.initial_world),
      edge_count: MapSet.size(model.edges),
      atoms: model.valuations |> Map.keys() |> Enum.sort(),
      warning: Enum.map(model.warnings, &warning_message/1)
    }
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

  defp world_name(index), do: "i#{index + 1}"

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

  defp blocking_axiom(model, include_atoms) do
    case Code.ensure_loaded(Src.Core.Axiom) do
      {:module, _} ->
        apply(Src.Core.Axiom, :blocking_axiom, [model, [include_atoms: include_atoms]])
      _ ->
        raise "Src.Core.Axiom.blocking_axiom/2 is not implemented yet."
    end
  end
end
