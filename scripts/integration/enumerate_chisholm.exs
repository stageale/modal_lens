alias Src.ModelEnumeration

project_root =
  __DIR__
  |> Path.join("../..")
  |> Path.expand()

theory_path =
  Path.join([
    project_root,
    "examples",
    "input",
    "Chisholm.thy"
  ])

output_dir =
  Path.join([
    project_root,
    "out",
    "chisholm_enumeration"
  ])

isabelle_bin =
  System.get_env("AXIOM_REFINER_ISABELLE_BIN") ||
    "/usr/bin/isabelle"

IO.puts("""
Starting Chisholm countermodel enumeration

Base theory:
  #{theory_path}

Output directory:
  #{output_dir}

Maximum countermodels:
  3
""")

result =
  ModelEnumeration.enumerate(
    theory_path,
    isabelle_bin: isabelle_bin,
    relation: "R",
    atoms: ["go", "tell"],
    render_atoms: ["go", "tell"],
    include_atoms: true,
    max_models: 3,
    output_dir: output_dir,
    axiom_option: :SDL,
    query: "holds_at_actual (O tell)",
    threads: 2
  )

case result do
  {:ok, enumeration} ->
    IO.puts("\nEnumeration completed.")
    IO.puts("Status: #{inspect(enumeration.status)}")
    IO.puts("Countermodels found: #{enumeration.model_count}")

    enumeration.countermodels
    |> Enum.each(fn entry ->
      IO.puts("""

      Countermodel #{entry.iteration}
        Search theory: #{entry.search_theory_file}
        Nitpick output: #{entry.nitpick_output_file}
        SVG: #{entry.graph_svg_file}
        Blocking axiom: #{entry.blocking_axiom_file}
        Next theory: #{Map.get(entry, :next_search_theory_file, "none")}
      """)
    end)

    IO.puts("\nGenerated SVG files:")

    enumeration.svg_files
    |> Enum.each(fn svg ->
      exists? = File.exists?(svg)

      IO.puts(
        "  #{if exists?, do: "✓", else: "✗"} #{svg}"
      )
    end)

    IO.puts("\nOutput directory:")
    IO.puts("  #{enumeration.output_dir}")

  {:error, reason} ->
    IO.puts(:stderr, "\nEnumeration failed:")

    IO.inspect(
      reason,
      pretty: true,
      limit: :infinity,
      printable_limit: :infinity
    )

    System.halt(1)
end
