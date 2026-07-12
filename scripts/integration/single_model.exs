defmodule SingleModel do
  alias Src.Core.BlockingAxiom
	alias Src.Core.Model
	alias Src.Core.Parser
	alias Src.Core.Render
	alias Src.Interface.Isabelle.Client

	def main([theory_path]) do
	  run(theory_path)
	end

	def main([]) do
  	abort("""
  	Missing Isabelle theory file.

	  Usage:
  	  mix run scripts/integration/single_model.exs -- THEORY.thy
  	""")
	end

	def main(arguments) do
  	abort("""
  	Expected exactly one Isabelle theory file.

	  Received:
  	  #{inspect(arguments)}
  	""")
	end

	defp run(theory_path) do
		theory_path = Path.expand(theory_path)
		theory_stem = Path.basename(theory_path, ".thy")

		out_dir = Path.join(["out", "phase1", theory_stem])
							|> Path.expand()

		File.mkdir_p!(out_dir)

		nitpick_output_path =
			Path.join(out_dir, "#{theory_stem}.nitpick.txt")

		IO.puts("Phase 1: single SDL countermodel")
		IO.puts("Theory: #{theory_path}")
		IO.puts("Output: #{out_dir}")
		IO.puts("")

		client_opts =
			[
				output_file: nitpick_output_path
			]
			|> maybe_put(
				:isabelle_bin,
				System.get_env("AXIOM_REFINER_ISABELLE_BIN")
			)

		case Client.nitpick_theory(theory_path, client_opts) do
			{:ok, run} ->
				IO.puts("CHECK Isabelle build completed")
				IO.puts("      Session: #{run.session_name}")
				IO.puts("      Log: #{run.output_file}")

				process_nitpick_output(run, out_dir)

			{:error, reason} ->
				IO.puts(:stderr, "FAIL  Isabelle execution failed")
				IO.puts(:stderr, format_error(reason))
				System.halt(1)
		end
	end

	defp process_nitpick_output(run, out_dir) do
	  atoms = ["go", "tell"]

  	parser_opts = [
    	relation: "R",
  	  atoms: atoms,
    	auto_atoms: false
	  ]

		model =
			try do
				Parser.parse_nitpick_file(run.output_file, parser_opts)
			rescue
				exception ->
          IO.puts(:stderr, "")
          IO.puts(:stderr, "FAIL  Nitpick output could not be parsed")
          IO.puts(:stderr, "      " ++ Exception.message(exception))
          IO.puts(:stderr, "")
          IO.puts(:stderr, "      Inspect the captured Isabelle output:")
          IO.puts(:stderr, "      less #{run.output_file}")

          System.halt(2)
			end

		IO.puts("CHECK  Nitpick model parsed")
		print_model_summary(model)

		artifacts =
			write_model_artifacts(
				model,
				out_dir,
				atoms,
				run.theory_name
			)

    IO.puts("")
    IO.puts("Generated artifacts:")
    IO.puts("      DOT graph:       #{artifacts.dot}")

    if artifacts.svg do
      IO.puts("      SVG graph:       #{artifacts.svg}")
    else
      IO.puts("      SVG graph:       not generated (GraphViz not found)")
    end

    IO.puts("      Blocking axiom:  #{artifacts.blocking_axiom}")
    IO.puts("")
    IO.puts("CHECK Phase 1 completed")
	end

	defp write_model_artifacts(model, out_dir, atoms, theory_name) do
		dot_path = Path.join(out_dir, "countermodel_001.dot")
		svg_path = Path.join(out_dir, "countermodel_001.svg")

		Render.write_dot(
			model,
			dot_path,
			atoms: atoms
		)

		rendered_svg =
			if System.find_executable("dot") do
				Render.render_dot(
					dot_path,
					fmt: "svg",
					output_path: svg_path
				)
			else
				nil
			end
		blocking_axiom =
			BlockingAxiom.blocking_axiom(
				model,
				name: "#{theory_name}_countermodel_001",
				include_atoms: true
			)

		blocking_path =
			Path.join(out_dir, "blocking_axiom_001.thyfrag")

		File.write!(blocking_path, blocking_axiom <> "\n")

		%{
			dot: dot_path,
			svg: rendered_svg,
			blocking_axiom: blocking_path
		}
	end

	defp print_model_summary(%Model{} = model) do
    IO.puts("  Kind:          #{model.kind}")
    IO.puts("  Worlds:        #{model.cardinality}")
    IO.puts("  Initial world: #{Model.world_name(model, model.initial_world)}")
    IO.puts("  Relation:      #{model.relation_name}")
    IO.puts("  Edges:         #{Model.edge_count(model)}")
    IO.puts("  Atoms:         #{Enum.join(Model.atom_names(model), ", ")}")

		Enum.each(Model.warning_messages(model), fn warning ->
      IO.puts("  Warning:       #{warning}")
		end)
	end

	defp maybe_put(opts, _key, nil), do: opts
	defp maybe_put(opts, _key, ""), do: opts
	defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp format_error(%{status: status, output: output}) do
    """
    Status: #{inspect(status)}

    #{output}
    """
  end

  defp format_error(reason), do: inspect(reason, pretty: true)

  defp abort(message) do
    IO.puts(:stderr, message)
    System.halt(64)
  end
end

SingleModel.main(System.argv())
