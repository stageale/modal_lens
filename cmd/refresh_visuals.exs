# Rebuild presentation artifacts from stored models without Isabelle, mining,
# clustering or LLM generation. Run with: mix run cmd/refresh_visuals.exs RUN_DIR
defmodule RefreshVisuals do
  alias Src.Core.Model.{DDL, EDSTIT, Modality, SDL}
  alias Src.Explanation.Visual.{GraphViewExport, Highlight, Palette, Render}
  alias Src.Interface.Ui.Page

  def run(directory) do
    base = Path.expand(directory)
    html_path = Path.join(base, "index.html")
    html = File.read!(html_path)
    [_, suffix] = String.split(html, "const variants = ", parts: 2)
    [encoded | _] = String.split(suffix, ";\n", parts: 2)
    variants = Jason.decode!(encoded)

    updated = Enum.map(variants, fn variant ->
      round = get_in(variant, ["refinement", "round"])
      stage_dir = if round, do: Path.join(base, "refinement/round-#{pad(round)}"), else: base
      report = read_json(Path.join(stage_dir, "report.json"))
      patterns = Map.new(report["clusters"], &{&1["cluster_id"], &1["characteristic_patterns"]})
      files = Path.wildcard(Path.join(stage_dir, "cardinality_*/iteration_*/model.json"))
      files = if files == [], do: Path.wildcard(Path.join(stage_dir, "iteration_*/model.json")), else: files
      if length(files) != length(report["highlights"]), do: raise("Model/report count mismatch")

      records = files |> Enum.sort() |> Enum.with_index() |> Map.new(fn {file, index} ->
        document = read_json(file)
        metadata = document["metadata"]
        key = {document["model"]["cardinality"], metadata["iteration"]}
        entry = Enum.at(report["highlights"], index)
        {key, {file, document, entry, patterns[entry["cluster_id"]] || []}}
      end)

      clusters = Enum.map(variant["result"]["clusters"], fn cluster ->
        models = Enum.map(cluster["models"], fn ui_model ->
          key = {ui_model["model_summary"]["cardinality"], ui_model["iteration"]}
          {file, document, entry, cluster_patterns} = Map.fetch!(records, key)
          model = to_model(document["model"])
          highlight = to_highlight(entry["highlight"])
          palettes = Map.new(Palette.names(), &{Atom.to_string(&1), &1})
          palette = Map.fetch!(palettes, variant["options"]["palette"] || "turbo")
          opts = [atoms: document["model"]["atoms"], palette: palette, highlight: highlight]
          output = Path.dirname(file)
          paths = %{graph_dot_file: Path.join(output, "model.dot"),
                    graph_svg_file: Path.join(output, "model.svg"),
                    graph_tikz_file: Path.join(output, "model.tex")}
          Render.write_dot(model, paths.graph_dot_file, opts)
          Render.render_dot(paths.graph_dot_file, fmt: "svg", output_path: paths.graph_svg_file)
          Render.write_tikz(model, paths.graph_tikz_file, opts)
          ui_model = assign_asset_paths(ui_model, paths, variant["run"]["id"])
          copy_assets(base, paths, ui_model)

          if match?(%EDSTIT{}, model) do
            views = GraphViewExport.write_all(model, output, Keyword.put(opts, :existing_full, paths))
            copied_views = Map.new(ui_model["graph_views"]["views"], fn {id, destination} ->
              source = Map.fetch!(views.views, id)
              destination = assign_asset_paths(destination, source, variant["run"]["id"], ui_model["iteration"])
              copy_assets(base, source, destination)
              {id, destination}
            end)
            ui_model = put_in(ui_model, ["graph_views", "views"], copied_views)
            Map.put(ui_model, "highlight_status", highlight_status(entry, cluster_patterns))
          else
            Map.put(ui_model, "highlight_status", highlight_status(entry, cluster_patterns))
          end
        end)
        Map.put(cluster, "models", models)
      end)
      put_in(variant, ["result", "clusters"], clusters)
    end)

    File.write!(html_path, Page.render(updated))
    IO.puts("Refreshed #{base}")
  end

  defp to_model(data) do
    designated = data["designated_world"]
    world = if is_map(designated), do: designated["index"], else: designated
    common = %{cardinality: data["cardinality"], valuations: data["valuations"],
               kind: Map.fetch!(%{"model" => :model, "countermodel" => :countermodel}, data["kind"] || "countermodel")}
    case data["logic"] do
      "ed_stit" ->
        modalities = Enum.map(data["modalities"], fn item ->
          kind = Map.fetch!(%{"settledness" => :settledness, "stit" => :stit,
                              "ought" => :ought, "belief" => :belief}, item["kind"])
          Modality.new!(item["symbol"], kind,
                        Enum.map(item["accessibility"], &List.to_tuple/1), agent: item["agent"])
        end)
        struct!(EDSTIT, Map.merge(common, %{actual_world: world, agents: data["agents"], modalities: modalities}))
      logic when logic in ["sdl", "ddl"] ->
        module = if logic == "sdl", do: SDL, else: DDL
        designated_key = if logic == "sdl", do: :initial_world, else: :actual_world
        fields = Map.merge(common, %{relation_name: data["relation"],
                                   edges: MapSet.new(Enum.map(data["edges"], &List.to_tuple/1))})
        struct!(module, Map.put(fields, designated_key, world))
    end
  end

  defp to_highlight(nil), do: nil
  defp to_highlight(data) do
    Highlight.new(basis: :pattern, scope: :cluster,
      world_scores: Map.new(data["world_scores"], &{&1["world"], &1["score"]}),
      edge_scores: Map.new(data["edge_scores"], &{{&1["source"], &1["target"]}, &1["score"]}))
  end

  defp copy_assets(base, source, destination) do
    Enum.each([:graph_svg_file, :graph_tikz_file], fn key ->
      relative = destination[Atom.to_string(key)]
      if relative do
        target = Path.expand(relative, base)
        unless String.starts_with?(target, base <> "/assets/"), do: raise("Invalid asset path")
        File.mkdir_p!(Path.dirname(target))
        File.cp!(Map.fetch!(source, key), target)
      end
    end)
  end

  defp assign_asset_paths(destination, source, run_id, iteration \\ nil) do
    iteration = iteration || destination["iteration"]
    Enum.reduce([:graph_svg_file, :graph_tikz_file], destination, fn key, acc ->
      path = Map.fetch!(source, key)
      source_id = :crypto.hash(:sha256, path) |> Base.encode16(case: :lower) |> binary_part(0, 12)
      relative = "assets/#{run_id}-model-#{iteration}-#{source_id}-#{Path.basename(path)}"
      Map.put(acc, Atom.to_string(key), relative)
    end)
  end

  defp highlight_status(entry, patterns) do
    cond do
      entry["highlight"] != nil -> "applied"
      patterns == [] -> "no_characteristic_pattern"
      true -> "no_occurrence_in_model"
    end
  end

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()
  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(3, "0")
end

case System.argv() do
  [] -> raise "Usage: mix run cmd/refresh_visuals.exs RUN_DIR [RUN_DIR ...]"
  directories -> Enum.each(directories, &RefreshVisuals.run/1)
end
