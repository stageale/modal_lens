defmodule Src.Interface.Ui.Page do
  @moduledoc """
  Writes an interactive HTML view for a calculated UI session.
  """

  alias Src.Interface.Ui.Session
  alias Src.Interface.Ui.View

  @doc "Renders the complete HTML document."
  @spec render([map()]) :: String.t()
  def render(variants) when is_list(variants) do
    variants = encode_variants(variants)

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>ModalLens</title>
      <style>
        body {
          max-width: 1100px;
          margin: 0 auto;
          padding: 2rem;
          font-family: system-ui, sans-serif;
          background: #f6f7f9;
          color: #20242a;
        }

        header,
        main {
          background: white;
          padding: 1.5rem;
          border-radius: 12px;
          margin-bottom: 1rem;
        }

        select {
          min-width: 260px;
          padding: 0.5rem;
        }

        pre {
          white-space: pre-wrap;
          overflow-wrap: anywhere;
          background: #f1f3f5;
          padding: 1rem;
          border-radius: 8px;
        }

        img {
          max-width: 100%;
        }

        .cluster {
          border-top: 1px solid #d8dde3;
          padding-top: 1.5rem;
          margin-top: 1.5rem;
        }

        .cluster-text {
          padding: 1rem;
          border-left: 4px solid #495057;
          background: #f1f3f5;
        }

        .models {
          display: grid;
          grid-template-columns:
            repeat(auto-fit, minmax(300px, 1fr));
          gap: 1rem;
          margin-top: 1rem;
        }

        .model {
          border: 1px solid #d8dde3;
          border-radius: 10px;
          padding: 1rem;
        }

        .model img {
          width: 100%;
          height: auto;
        }

        .tikz-preview {
          width: 100%;
          height: 28rem;
          border: 1px solid #d8dde3;
          border-radius: 8px;
          background: white;
        }

        .graph-links {
          display: flex;
          flex-wrap: wrap;
          gap: 1rem;
          margin: 0.75rem 0;
        }

        .graph-links a {
          font-weight: 600;
        }
      </style>
    </head>
    <body>
      <header>
        <h1>ModalLens</h1>

        <label>
          Calculated configuration
          <select id="variant"></select>
        </label>
      </header>

      <main>
        <h2 id="run-title"></h2>
        <pre id="options"></pre>
        <p id="summary"></p>
        <div id="clusters"></div>
      </main>

      <script>
        const variants = #{variants};
        const selector = document.getElementById("variant");

        variants.forEach((variant, index) => {
          const option = document.createElement("option");
          option.value = index;
          option.textContent = variant.run.id;
          selector.appendChild(option);
        });

        function showVariant(index) {
          const variant = variants[index];
          const result = variant.result || {};
          const clusters = result.clusters || [];
          const clusterVerbs = new Map(
            (result.cluster_verbs || []).map(entry => [
              entry.cluster_id,
              entry
            ])
          );

          document.getElementById("run-title").textContent =
            variant.run.id + " · " + variant.run.status;

          document.getElementById("options").textContent =
            JSON.stringify(variant.options, null, 2);

          document.getElementById("summary").textContent =
            (result.model_count || 0) +
            " models · " +
            clusters.length +
            " clusters";

          const container = document.getElementById("clusters");
          container.replaceChildren();

          clusters.forEach(cluster => {
            const section = document.createElement("section");
            section.className = "cluster";

            const title = document.createElement("h3");
            title.textContent =
              "Cluster " +
              cluster.cluster_id +
              " · " +
              cluster.model_count +
              " models";

            section.appendChild(title);

            const verb = clusterVerbs.get(cluster.cluster_id);
            const explanation = document.createElement("p");
            explanation.className = "cluster-text";
            explanation.textContent =
              verb?.text || "No verbalization generated.";

            section.appendChild(explanation);

            if ((cluster.characteristic_patterns || []).length > 0) {
              const details = document.createElement("details");
              const summary = document.createElement("summary");
              const patterns = document.createElement("pre");

              summary.textContent = "Characteristic patterns";
              patterns.textContent = JSON.stringify(
                cluster.characteristic_patterns,
                null,
                2
              );

              details.append(summary, patterns);
              section.appendChild(details);
            }

            const models = document.createElement("div");
            models.className = "models";

            (cluster.models || []).forEach(model => {
              const article = document.createElement("article");
              article.className = "model";

              const heading = document.createElement("h4");
              heading.textContent = "Model " + model.iteration;
              article.appendChild(heading);

              const tikzSelected =
                variant.options.graph_format === "tikz";

              if (tikzSelected && model.graph_pdf_file) {
                const preview = document.createElement("object");

                preview.data = model.graph_pdf_file;
                preview.type = "application/pdf";
                preview.className = "tikz-preview";

                const fallbackLink = document.createElement("a");
                fallbackLink.href = model.graph_pdf_file;
                fallbackLink.textContent = "Open TikZ PDF";
                fallbackLink.target = "_blank";
                fallbackLink.rel = "noopener";

                preview.appendChild(fallbackLink);
                article.appendChild(preview);
              } else if (model.graph_svg_file) {
                const image = document.createElement("img");

                image.src = model.graph_svg_file;
                image.alt =
                  "Heatmap for model " + model.iteration;

                article.appendChild(image);
              }

              if (
                tikzSelected &&
                (model.graph_pdf_file || model.graph_tikz_file)
              ) {
                const links = document.createElement("div");
                links.className = "graph-links";

                if (model.graph_pdf_file) {
                  const pdfLink = document.createElement("a");

                  pdfLink.href = model.graph_pdf_file;
                  pdfLink.textContent = "Open PDF";
                  pdfLink.target = "_blank";
                  pdfLink.rel = "noopener";

                  links.appendChild(pdfLink);
                }

                if (model.graph_tikz_file) {
                  const sourceLink = document.createElement("a");

                  sourceLink.href = model.graph_tikz_file;
                  sourceLink.textContent = "Open TikZ source";
                  sourceLink.target = "_blank";
                  sourceLink.rel = "noopener";

                  links.appendChild(sourceLink);
                }

                article.appendChild(links);
              }
              const modelDetails = document.createElement("details");
              const modelSummary = document.createElement("summary");
              const modelData = document.createElement("pre");

              modelSummary.textContent = "Model data";
              modelData.textContent = JSON.stringify(
                model.model_summary || {},
                null,
                2
              );

              modelDetails.append(modelSummary, modelData);
              article.appendChild(modelDetails);

              if (model.blocking_axiom) {
                const axiomDetails =
                  document.createElement("details");
                const axiomSummary =
                  document.createElement("summary");
                const axiom = document.createElement("pre");

                axiomSummary.textContent = "Blocking axiom";
                axiom.textContent = model.blocking_axiom;

                axiomDetails.append(axiomSummary, axiom);
                article.appendChild(axiomDetails);
              }

              models.appendChild(article);
            });

            section.appendChild(models);
            container.appendChild(section);
          });
        }
        selector.addEventListener("change", event => {
          showVariant(Number(event.target.value));
        });

        if (variants.length > 0) {
          showVariant(0);
        }
      </script>
    </body>
    </html>
    """
  end

  @doc "Writes the session view and its graph assets to an HTML file."
  @spec write(Session.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write(%Session{} = session, path) when is_binary(path) do
    path = Path.expand(path)
    html_dir = Path.dirname(path)
    assets_dir = Path.join(html_dir, "assets")

    with :ok <- File.mkdir_p(assets_dir),
        {:ok, variants} <- prepare_variants(session, assets_dir, html_dir),
         :ok <- File.write(path, render(variants)) do
           {:ok, path}
         end
  end

  defp encode_variants(variants) do
    variants
    |> Jason.encode!()
    |> String.replace("</", "<\\/")
  end

  defp prepare_variants(session, assets_dir, html_dir) do
    try do
      variants =
        session
        |> View.variants()
        |> Enum.map(&copy_variant_graphs(&1, assets_dir, html_dir))

      {:ok, variants}
    rescue
      error ->
        {:error,
         {:cannot_prepare_ui_assets,
          Exception.message(error)}}
    end
  end

  defp copy_variant_graphs(%{result: nil} = variant, _assets_dir, _html_dir), do: variant

  defp copy_variant_graphs(%{result: result} = variant, assets_dir, html_dir) do
    run_id = variant.run["id"]

    clusters =
      result
      |> Map.get(:clusters, [])
      |> Enum.map(fn cluster ->
        models =
          cluster
          |> Map.get(:models, [])
          |> Enum.map(
            &copy_model_graphs(&1, run_id, assets_dir, html_dir)
          )

        Map.put(cluster, :models, models)
      end)

    put_in(variant, [:result, :clusters], clusters)
  end

  defp copy_model_graphs(model, run_id, assets_dir, html_dir) do
    [:graph_svg_file, :graph_tikz_file, :graph_pdf_file]
    |> Enum.reduce(model, fn key, current_model ->
      copy_model_artifact(current_model, key, run_id, assets_dir, html_dir)
    end)
  end

  defp copy_model_artifact(model, key, run_id, assets_dir, html_dir) do
    case Map.get(model, key) do
      nil -> model

      source ->
        target =
          Path.join(
            assets_dir,
            "#{run_id}-model-#{model.iteration}-#{Path.basename(source)}"
          )

        File.cp!(source, target)

        relative_path =
          target
          |> Path.relative_to(html_dir)
          |> String.replace("\\", "/")

        Map.put(model, key, relative_path)
    end
  end
end
