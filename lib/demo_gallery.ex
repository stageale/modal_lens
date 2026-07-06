defmodule Src.VisualExplanations.DemoGallery do
  @moduledoc """
  Demo module for visual axiom-refinement explanations.

  It parses one of the bundled example families (`:chisholm`, `:mcube`, or `:all`),
  computes frame-condition violations, renders highlighted DOT/SVG files for every
  selected axiom, and writes a small static HTML GUI.

  Usage from the project root:

      iex -S mix
      Src.VisualExplanations.DemoGallery.run(:all, limit: 4, open?: true)
      Src.VisualExplanations.DemoGallery.run(:chisholm, axioms: [:transitive, :symmetric])
      Src.VisualExplanations.DemoGallery.run(:mcube, render_fmt: "png")
  """

  alias Src.Core.Model
  alias Src.Core.Parser
  alias Src.Core.Render
  alias Src.HardcodedRefinement.AxiomScoring
  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.VisualExplanations.AxiomExplanation
  alias Src.VisualExplanations.Highlight

  @examples [:chisholm, :mcube, :all]

  def available_examples, do: @examples

  def run(example \\ :all, opts \\ []) when example in @examples do
    out_dir = Keyword.get(opts, :out_dir, "demo_output/axiom_gallery")
    axioms = Keyword.get(opts, :axioms, AxiomExplanation.supported_axioms())
    render? = Keyword.get(opts, :render?, true)
    render_fmt = Keyword.get(opts, :render_fmt, "svg")

    File.rm_rf!(out_dir)
    File.mkdir_p!(out_dir)

    entries =
      example
      |> input_files(opts)
      |> Enum.map(&parse_entry(&1, opts))

    ranked_axioms = rank_axioms(entries, axioms)
    cards = render_cards(entries, axioms, out_dir, render?, render_fmt)
    html_path = write_gui(out_dir, example, entries, ranked_axioms, cards)

    maybe_open(html_path, Keyword.get(opts, :open?, false))

    %{
      example: example,
      out_dir: out_dir,
      html_path: html_path,
      ranked_axioms: ranked_axioms,
      entries: entries,
      cards: cards
    }
  end

  def run(example, _opts) do
    raise ArgumentError,
          "unknown demo example #{inspect(example)}; expected one of #{inspect(@examples)}"
  end

  defp input_files(:all, opts) do
    input_files(:chisholm, opts) ++ input_files(:mcube, opts)
  end

  defp input_files(:chisholm, opts) do
    examples_dir = Keyword.get(opts, :examples_dir, "examples/input")

    examples_dir
    |> Path.join("chisholm*.txt")
    |> Path.wildcard()
    |> Enum.sort()
    |> limit_files(opts)
    |> Enum.map(fn file -> %{example: :chisholm, file: file} end)
  end

  defp input_files(:mcube, opts) do
    examples_dir = Keyword.get(opts, :examples_dir, "examples/input")

    [examples_dir, "mcubeinput", "*.txt"]
    |> Path.join()
    |> Path.wildcard()
    |> Enum.sort()
    |> limit_files(opts)
    |> Enum.map(fn file -> %{example: :mcube, file: file} end)
  end

  defp limit_files(files, opts) do
    case Keyword.get(opts, :limit, 6) do
      :all -> files
      n when is_integer(n) and n > 0 -> Enum.take(files, n)
      _ -> files
    end
  end

  defp parse_entry(%{example: example, file: file}, opts) do
    atoms = Keyword.get(opts, :atoms, default_atoms(example))
    auto_atoms = Keyword.get(opts, :auto_atoms, atoms == :auto)
    atoms = if atoms == :auto, do: [], else: atoms

    model =
      Parser.parse_nitpick_file(file,
        relation: Keyword.get(opts, :relation, "R"),
        atoms: atoms,
        auto_atoms: auto_atoms
      )

    worlds = FrameAnalysis.worlds_for_model(model)
    analysis = FrameAnalysis.analysis_from_model(model)

    %{
      id: source_id(file),
      example: example,
      file: file,
      atoms: atoms,
      model: model,
      worlds: worlds,
      analysis: analysis
    }
  end

  defp default_atoms(:chisholm), do: ["go", "tell"]
  defp default_atoms(:mcube), do: []

  defp rank_axioms(entries, axioms) do
    entries
    |> Enum.flat_map(fn entry ->
      AxiomScoring.ranked_suggestions(entry.analysis, entry.worlds, entry.model.edges)
    end)
    |> Enum.filter(fn metric -> metric.axiom in axioms end)
    |> Enum.group_by(fn metric -> metric.axiom end)
    |> Enum.map(fn {axiom, metrics} ->
      %{
        axiom: axiom,
        score: metrics |> Enum.map(& &1.score) |> Enum.sum(),
        violations: metrics |> Enum.map(& &1.violations) |> Enum.sum(),
        support: metrics |> Enum.map(& &1.support) |> Enum.sum(),
        affected_models: Enum.count(metrics, fn metric -> metric.violations > 0 end)
      }
    end)
    |> Enum.sort_by(fn row -> {row.score, row.violations, row.affected_models} end, :desc)
  end

  defp render_cards(entries, axioms, out_dir, render?, render_fmt) do
    for axiom <- axioms,
        entry <- entries do
      explanation = AxiomExplanation.explain(entry.analysis, axiom)
      highlight = Highlight.from_explanation(explanation)

      axiom_dir = Path.join([out_dir, "assets", Atom.to_string(axiom)])
      File.mkdir_p!(axiom_dir)

      dot_path = Path.join(axiom_dir, "#{entry.id}.dot")

      Render.write_dot(entry.model, dot_path,
        atoms: entry.atoms,
        highlight: highlight
      )

      {image_path, render_error} = render_image(dot_path, render?, render_fmt)

      %{
        id: "#{entry.id}-#{axiom}",
        model_id: entry.id,
        example: entry.example,
        axiom: axiom,
        status: explanation.status,
        summary: explanation.summary,
        formula: explanation.formula,
        violations: explanation.violations,
        violation_count: length(explanation.violations),
        dot_path: dot_path,
        image_path: image_path,
        render_error: render_error
      }
    end
  end

  defp render_image(dot_path, false, _fmt), do: {nil, nil}

  defp render_image(dot_path, true, fmt) do
    try do
      {Render.render_dot(dot_path, fmt: fmt), nil}
    rescue
      exc -> {nil, Exception.message(exc)}
    end
  end

  defp write_gui(out_dir, selected_example, entries, ranked_axioms, cards) do
    html_path = Path.join(out_dir, "index.html")

    File.write!(
      html_path,
      html_document(selected_example, entries, ranked_axioms, cards, out_dir)
    )

    html_path
  end

  defp html_document(selected_example, entries, ranked_axioms, cards, out_dir) do
    examples = entries |> Enum.map(& &1.example) |> Enum.uniq()
    axioms = cards |> Enum.map(& &1.axiom) |> Enum.uniq()
    models = entries |> Enum.map(& &1.id)

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Axiom Refinement Demo Gallery</title>
      <style>
        :root { font-family: system-ui, -apple-system, Segoe UI, sans-serif; color: #1f2937; background: #f8fafc; }
        body { margin: 0; padding: 24px; }
        header { max-width: 1180px; margin: 0 auto 20px auto; }
        h1 { margin: 0 0 8px 0; font-size: 28px; }
        .subtitle { color: #64748b; margin: 0; }
        .panel { max-width: 1180px; margin: 0 auto 18px auto; background: white; border: 1px solid #e5e7eb; border-radius: 16px; padding: 16px; box-shadow: 0 8px 24px rgba(15,23,42,.05); }
        .controls { display: flex; flex-wrap: wrap; gap: 12px; align-items: end; }
        label { display: grid; gap: 5px; font-size: 13px; font-weight: 600; color: #475569; }
        select { min-width: 180px; padding: 9px 10px; border-radius: 10px; border: 1px solid #cbd5e1; background: white; }
        table { width: 100%; border-collapse: collapse; font-size: 14px; }
        th, td { text-align: left; padding: 8px 10px; border-bottom: 1px solid #e5e7eb; }
        th { color: #475569; font-weight: 700; }
        .best { color: #b91c1c; font-weight: 800; }
        .gallery { max-width: 1180px; margin: 0 auto; display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
        .card { background: white; border: 1px solid #e5e7eb; border-radius: 16px; overflow: hidden; box-shadow: 0 8px 24px rgba(15,23,42,.05); }
        .card-head { padding: 12px 14px; border-bottom: 1px solid #e5e7eb; display: grid; gap: 4px; }
        .card-title { font-weight: 800; }
        .meta { color: #64748b; font-size: 13px; }
        .status { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px; font-weight: 700; }
        .violated { background: #fee2e2; color: #991b1b; }
        .satisfied { background: #dcfce7; color: #166534; }
        .image-wrap { background: #f8fafc; min-height: 220px; display: grid; place-items: center; padding: 10px; }
        .image-wrap img { max-width: 100%; height: auto; }
        .card-body { padding: 12px 14px; font-size: 13px; color: #475569; }
        code { background: #f1f5f9; padding: 1px 4px; border-radius: 4px; }
        .links { margin-top: 8px; display: flex; gap: 10px; flex-wrap: wrap; }
        a { color: #2563eb; text-decoration: none; }
        a:hover { text-decoration: underline; }
        .legend { display: flex; flex-wrap: wrap; gap: 12px; margin-top: 10px; color: #475569; font-size: 13px; }
        .sample-line { display: inline-flex; align-items: center; gap: 6px; }
        .red-line, .dashed-line { width: 36px; border-top: 3px solid #dc2626; display: inline-block; }
        .dashed-line { border-top-style: dashed; }
      </style>
    </head>
    <body>
      <header>
        <h1>Axiom Refinement Demo Gallery</h1>
        <p class="subtitle">Selected run: <code>#{escape_html(selected_example)}</code>. Responsible edges are red; missing edges are red and dashed.</p>
      </header>

      <section class="panel">
        <div class="controls">
          <label>Example
            <select id="exampleFilter" onchange="filterCards()">
              <option value="all">all</option>
              #{option_tags(examples)}
            </select>
          </label>
          <label>Axiom
            <select id="axiomFilter" onchange="filterCards()">
              <option value="all">all</option>
              #{option_tags(axioms)}
            </select>
          </label>
          <label>Model
            <select id="modelFilter" onchange="filterCards()">
              <option value="all">all</option>
              #{option_tags(models)}
            </select>
          </label>
        </div>
        <div class="legend">
          <span class="sample-line"><span class="red-line"></span> responsible edge</span>
          <span class="sample-line"><span class="dashed-line"></span> missing edge</span>
        </div>
      </section>

      <section class="panel">
        <h2>Axiom ranking</h2>
        #{score_table(ranked_axioms)}
      </section>

      <main class="gallery" id="gallery">
        #{cards_html(cards, out_dir)}
      </main>

      <script>
        function filterCards() {
          const example = document.getElementById('exampleFilter').value;
          const axiom = document.getElementById('axiomFilter').value;
          const model = document.getElementById('modelFilter').value;

          document.querySelectorAll('.card').forEach(card => {
            const okExample = example === 'all' || card.dataset.example === example;
            const okAxiom = axiom === 'all' || card.dataset.axiom === axiom;
            const okModel = model === 'all' || card.dataset.model === model;
            card.style.display = (okExample && okAxiom && okModel) ? '' : 'none';
          });
        }
      </script>
    </body>
    </html>
    """
  end

  defp score_table([]), do: "<p>No scores available.</p>"

  defp score_table(rows) do
    body =
      rows
      |> Enum.with_index(1)
      |> Enum.map(fn {row, index} ->
        class = if index == 1, do: " class=\"best\"", else: ""

        """
        <tr#{class}>
          <td>#{index}</td>
          <td><code>#{escape_html(row.axiom)}</code></td>
          <td>#{format_score(row.score)}</td>
          <td>#{row.violations}</td>
          <td>#{row.affected_models}</td>
          <td>#{row.support}</td>
        </tr>
        """
      end)
      |> Enum.join("\n")

    """
    <table>
      <thead>
        <tr><th>#</th><th>Axiom</th><th>score</th><th>violations</th><th>affected models</th><th>support</th></tr>
      </thead>
      <tbody>#{body}</tbody>
    </table>
    """
  end

  defp cards_html(cards, out_dir) do
    cards
    |> Enum.map(fn card ->
      image =
        case card.image_path do
          nil ->
            reason = card.render_error || "rendering disabled"
            "<p>#{escape_html(reason)}</p>"

          path ->
            rel = relative_to(path, out_dir)
            "<img src=\"#{escape_attr(rel)}\" alt=\"#{escape_attr(card.model_id)} #{escape_attr(card.axiom)}\">"
        end

      dot_rel = relative_to(card.dot_path, out_dir)
      status_class = Atom.to_string(card.status)

      """
      <article class="card" data-example="#{escape_attr(card.example)}" data-axiom="#{escape_attr(card.axiom)}" data-model="#{escape_attr(card.model_id)}">
        <div class="card-head">
          <div class="card-title">#{escape_html(card.model_id)} · <code>#{escape_html(card.axiom)}</code></div>
          <div class="meta"><span class="status #{status_class}">#{escape_html(card.status)}</span> #{card.violation_count} violation(s)</div>
        </div>
        <div class="image-wrap">#{image}</div>
        <div class="card-body">
          <div><strong>Formula:</strong> <code>#{escape_html(card.formula)}</code></div>
          <div><strong>Summary:</strong> #{escape_html(card.summary)}</div>
          <div><strong>Violations:</strong> <code>#{escape_html(inspect(card.violations))}</code></div>
          <div class="links"><a href="#{escape_attr(dot_rel)}">DOT</a></div>
        </div>
      </article>
      """
    end)
    |> Enum.join("\n")
  end

  defp option_tags(values) do
    values
    |> Enum.map(fn value ->
      rendered = to_string(value)
      "<option value=\"#{escape_attr(rendered)}\">#{escape_html(rendered)}</option>"
    end)
    |> Enum.join("\n")
  end

  defp source_id(path) do
    path
    |> Path.basename(Path.extname(path))
    |> String.replace(~r/[^A-Za-z0-9_.-]+/, "_")
  end

  defp relative_to(nil, _base), do: nil
  defp relative_to(path, base), do: Path.relative_to(path, base)

  defp format_score(score) when is_float(score), do: :erlang.float_to_binary(score, decimals: 4)
  defp format_score(score), do: to_string(score)

  defp maybe_open(_path, false), do: :ok

  defp maybe_open(path, true) do
    cond do
      exe = System.find_executable("xdg-open") -> System.cmd(exe, [path])
      exe = System.find_executable("open") -> System.cmd(exe, [path])
      true -> :ok
    end
  end

  defp escape_html(value) do
    value
    |> to_string()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end

  defp escape_attr(value), do: escape_html(value)
end
