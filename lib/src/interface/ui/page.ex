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
        :root {
          color-scheme: light;
          --background: #f4f5f6;
          --surface: #ffffff;
          --surface-muted: #f8f9fa;
          --border: #d9dde2;
          --border-strong: #bbc2ca;
          --text: #1f2429;
          --text-muted: #69717a;
          --accent: #353b42;
        }

        * {
          box-sizing: border-box;
        }

        body {
          max-width: 1180px;
          margin: 0 auto;
          padding: 2rem;
          font-family:
            Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont,
            "Segoe UI", sans-serif;
          font-size: 15px;
          line-height: 1.5;
          background: var(--background);
          color: var(--text);
        }

        header,
        main {
          background: var(--surface);
          border: 1px solid var(--border);
        }

        header {
          padding: 1.5rem 1.75rem;
          margin-bottom: 1rem;
        }

        main {
          padding: 1.75rem;
        }

        h1,
        h2,
        h3,
        h4,
        p {
          margin-top: 0;
        }

        h1 {
          margin-bottom: 0.15rem;
          font-size: 1.55rem;
          font-weight: 650;
          letter-spacing: -0.02em;
        }

        h2 {
          margin-bottom: 1rem;
          font-size: 1.15rem;
          font-weight: 650;
        }

        h3 {
          margin-bottom: 0.35rem;
          font-size: 1rem;
          font-weight: 650;
        }

        h4 {
          margin-bottom: 0.75rem;
          font-size: 0.95rem;
          font-weight: 650;
        }

        .subtitle,
        .muted,
        .run-meta,
        .metric-label,
        .field-label {
          color: var(--text-muted);
        }

        .subtitle {
          margin: 0;
          font-size: 0.9rem;
        }

        .toolbar {
          display: flex;
          align-items: end;
          justify-content: space-between;
          gap: 1rem;
          margin-top: 1.25rem;
          padding-top: 1.25rem;
          border-top: 1px solid var(--border);
        }

        .toolbar label {
          display: grid;
          gap: 0.35rem;
          min-width: min(420px, 100%);
          font-size: 0.78rem;
          font-weight: 650;
          color: var(--text-muted);
          text-transform: uppercase;
          letter-spacing: 0.04em;
        }

        select {
          width: 100%;
          padding: 0.6rem 0.7rem;
          border: 1px solid var(--border-strong);
          border-radius: 3px;
          font: inherit;
          color: var(--text);
          background: var(--surface);
        }

        pre {
          margin: 0;
          white-space: pre-wrap;
          overflow-wrap: anywhere;
          font-family: "IBM Plex Mono", "SFMono-Regular", Consolas, monospace;
          font-size: 0.82rem;
          line-height: 1.55;
          background: var(--surface-muted);
          border: 1px solid var(--border);
          padding: 1rem;
        }

        summary {
          cursor: pointer;
          font-weight: 600;
        }

        details > :not(summary) {
          margin-top: 0.75rem;
        }

        .run-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 1rem;
          padding-bottom: 1.25rem;
          border-bottom: 1px solid var(--border);
        }

        .run-head h2 {
          margin: 0;
        }

        .run-meta {
          margin: 0;
          font-family: "IBM Plex Mono", "SFMono-Regular", Consolas, monospace;
          font-size: 0.78rem;
        }

        .metrics {
          display: grid;
          grid-template-columns: repeat(3, minmax(0, 1fr));
          border-bottom: 1px solid var(--border);
        }

        .metric {
          padding: 1rem 0;
        }

        .metric + .metric {
          padding-left: 1rem;
          border-left: 1px solid var(--border);
        }

        .metric-label,
        .field-label {
          display: block;
          margin-bottom: 0.2rem;
          font-size: 0.72rem;
          font-weight: 650;
          text-transform: uppercase;
          letter-spacing: 0.045em;
        }

        .metric-value {
          font-size: 1rem;
          font-weight: 600;
        }

        .configuration {
          padding: 1rem 0;
          border-bottom: 1px solid var(--border);
        }

        .refinement {
          margin: 1.5rem 0 0;
          border: 1px solid var(--border-strong);
          background: var(--surface);
        }

        .refinement-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 1rem;
          padding: 1rem 1.25rem;
          border-bottom: 1px solid var(--border);
          background: var(--surface-muted);
        }

        .refinement-head h2 {
          margin: 0;
        }

        .round-tag {
          font-family: "IBM Plex Mono", "SFMono-Regular", Consolas, monospace;
          font-size: 0.75rem;
          font-weight: 650;
          color: var(--text-muted);
        }

        .refinement-grid {
          display: grid;
          grid-template-columns: repeat(4, minmax(0, 1fr));
          border-bottom: 1px solid var(--border);
        }

        .refinement-field {
          min-width: 0;
          padding: 1rem 1.25rem;
        }

        .refinement-field + .refinement-field {
          border-left: 1px solid var(--border);
        }

        .field-value {
          overflow-wrap: anywhere;
          font-weight: 600;
        }

        .refinement-paths,
        .refinement-axiom,
        .refinement-details {
          padding: 1rem 1.25rem;
          border-bottom: 1px solid var(--border);
        }

        .refinement-details {
          border-bottom: 0;
        }

        .path-row + .path-row {
          margin-top: 0.75rem;
        }

        .path-value {
          font-family: "IBM Plex Mono", "SFMono-Regular", Consolas, monospace;
          font-size: 0.78rem;
          overflow-wrap: anywhere;
        }

        .section-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 1rem;
          margin-top: 2rem;
          padding-bottom: 0.75rem;
          border-bottom: 1px solid var(--border-strong);
        }

        .section-head h2 {
          margin: 0;
        }

        .cluster {
          padding: 1.5rem 0 0;
        }

        .cluster + .cluster {
          margin-top: 1.5rem;
          border-top: 1px solid var(--border-strong);
        }

        .cluster-head {
          display: flex;
          align-items: baseline;
          justify-content: space-between;
          gap: 1rem;
          margin-bottom: 1rem;
        }

        .cluster-head h3 {
          margin: 0;
        }

        .cluster-stat {
          color: var(--text-muted);
          font-size: 0.82rem;
        }

        .cluster-text {
          margin-bottom: 1rem;
          padding: 0.85rem 1rem;
          border-left: 2px solid var(--accent);
          background: var(--surface-muted);
        }

        .models {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
          gap: 1rem;
          margin-top: 1rem;
        }

        .model {
          min-width: 0;
          border: 1px solid var(--border);
          padding: 1rem;
          background: var(--surface);
        }

        .model img {
          display: block;
          width: 100%;
          height: auto;
          margin-bottom: 0.75rem;
          border: 1px solid var(--border);
          background: white;
        }

        .tikz-preview {
          width: 100%;
          height: 28rem;
          margin-bottom: 0.75rem;
          border: 1px solid var(--border);
          background: white;
        }

        .graph-links {
          display: flex;
          flex-wrap: wrap;
          gap: 1rem;
          margin: 0.75rem 0;
        }

        .graph-links a {
          color: var(--text);
          font-size: 0.82rem;
          font-weight: 600;
        }

        .empty-state {
          margin: 1rem 0 0;
          padding: 1rem;
          border: 1px dashed var(--border-strong);
          color: var(--text-muted);
          background: var(--surface-muted);
        }

        @media (max-width: 760px) {
          body {
            padding: 1rem;
          }

          header,
          main {
            padding: 1.15rem;
          }

          .toolbar,
          .run-head,
          .cluster-head,
          .section-head {
            align-items: stretch;
            flex-direction: column;
          }

          .metrics,
          .refinement-grid {
            grid-template-columns: 1fr;
          }

          .metric + .metric,
          .refinement-field + .refinement-field {
            padding-left: 0;
            border-left: 0;
            border-top: 1px solid var(--border);
          }

          .refinement-field {
            padding: 0.85rem 1rem;
          }
        }
      </style>
    </head>
    <body>
      <header>
        <h1>ModalLens</h1>
        <p class="subtitle">Semantic model analysis and structural refinement</p>

        <div class="toolbar">
          <label>
            Analysis stage
            <select id="variant"></select>
          </label>
        </div>
      </header>

      <main>
        <div class="run-head">
          <h2 id="run-title"></h2>
          <p class="run-meta" id="run-meta"></p>
        </div>

        <div class="metrics">
          <div class="metric">
            <span class="metric-label">Status</span>
            <span class="metric-value" id="status"></span>
          </div>
          <div class="metric">
            <span class="metric-label">Models</span>
            <span class="metric-value" id="model-count"></span>
          </div>
          <div class="metric">
            <span class="metric-label">Clusters</span>
            <span class="metric-value" id="cluster-count"></span>
          </div>
        </div>

        <details class="configuration">
          <summary>Execution configuration</summary>
          <pre id="options"></pre>
        </details>

        <section class="refinement" id="refinement" hidden>
          <div class="refinement-head">
            <h2>Refinement evidence</h2>
            <span class="round-tag" id="refinement-round"></span>
          </div>

          <div class="refinement-grid">
            <div class="refinement-field">
              <span class="field-label">Candidate</span>
              <span class="field-value" id="candidate-id"></span>
            </div>
            <div class="refinement-field">
              <span class="field-label">Cluster support</span>
              <span class="field-value" id="cluster-support"></span>
            </div>
            <div class="refinement-field">
              <span class="field-label">Outside support</span>
              <span class="field-value" id="outside-support"></span>
            </div>
            <div class="refinement-field">
              <span class="field-label">Graphlet</span>
              <span class="field-value" id="graphlet"></span>
            </div>
          </div>

          <div class="refinement-paths">
            <div class="path-row">
              <span class="field-label">Source pattern</span>
              <span class="path-value" id="source-pattern"></span>
            </div>
            <div class="path-row">
              <span class="field-label">Input theory</span>
              <span class="path-value" id="input-theory"></span>
            </div>
            <div class="path-row">
              <span class="field-label">Refined theory</span>
              <span class="path-value" id="refined-theory"></span>
            </div>
          </div>

          <div class="refinement-axiom">
            <span class="field-label">Applied Isabelle/HOL axiom</span>
            <pre id="refinement-axiom"></pre>
          </div>

          <details class="refinement-details">
            <summary>Candidate evidence</summary>
            <pre id="candidate-data"></pre>
          </details>
        </section>

        <div class="section-head">
          <h2>Structural evidence</h2>
          <span class="muted" id="structural-summary"></span>
        </div>

        <div id="clusters"></div>
      </main>

      <script>
        const variants = #{variants};
        const selector = document.getElementById("variant");

        function percentage(value) {
          if (typeof value !== "number") {
            return "—";
          }

          return (value * 100).toFixed(1) + "%";
        }

        function statusText(value) {
          if (!value) {
            return "unknown";
          }

          return String(value).replaceAll("_", " ");
        }

        variants.forEach((variant, index) => {
          const option = document.createElement("option");
          option.value = index;
          option.textContent = variant.stage?.label || variant.run.id;
          selector.appendChild(option);
        });

        function showRefinement(refinement) {
          const section = document.getElementById("refinement");

          if (!refinement) {
            section.hidden = true;
            return;
          }

          section.hidden = false;
          document.getElementById("refinement-round").textContent =
            "ROUND " + String(refinement.round).padStart(3, "0");
          document.getElementById("candidate-id").textContent =
            refinement.candidate_id || "—";
          document.getElementById("cluster-support").textContent =
            percentage(refinement.cluster_support);
          document.getElementById("outside-support").textContent =
            percentage(refinement.outside_support);
          document.getElementById("graphlet").textContent =
            refinement.graphlet_size
              ? refinement.graphlet_size + " worlds"
              : "—";
          document.getElementById("source-pattern").textContent =
            refinement.pattern_id
              ? refinement.pattern_id +
                " · cluster " +
                refinement.cluster_id
              : "—";
          document.getElementById("input-theory").textContent =
            refinement.input_theory_path || "—";
          document.getElementById("refined-theory").textContent =
            refinement.refined_theory_path || "—";
          document.getElementById("refinement-axiom").textContent =
            refinement.axiom || "—";
          document.getElementById("candidate-data").textContent =
            JSON.stringify(refinement.candidate || {}, null, 2);
        }

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
            variant.stage?.label || variant.run.id;
          document.getElementById("run-meta").textContent =
            variant.run.id;
          document.getElementById("status").textContent =
            statusText(result.status || variant.run.status);
          document.getElementById("model-count").textContent =
            result.model_count || 0;
          document.getElementById("cluster-count").textContent =
            clusters.length;
          document.getElementById("options").textContent =
            JSON.stringify(variant.options, null, 2);
          document.getElementById("structural-summary").textContent =
            (result.model_count || 0) +
            " models · " +
            clusters.length +
            " clusters";

          showRefinement(variant.refinement);

          const container = document.getElementById("clusters");
          container.replaceChildren();

          if (clusters.length === 0) {
            const empty = document.createElement("p");
            empty.className = "empty-state";
            empty.textContent = "No structural clusters were produced for this stage.";
            container.appendChild(empty);
            return;
          }

          clusters.forEach(cluster => {
            const section = document.createElement("section");
            section.className = "cluster";

            const clusterHead = document.createElement("div");
            clusterHead.className = "cluster-head";

            const title = document.createElement("h3");
            title.textContent = "Cluster " + cluster.cluster_id;

            const stats = document.createElement("span");
            stats.className = "cluster-stat";
            stats.textContent =
              cluster.model_count +
              " models" +
              (typeof cluster.model_fraction === "number"
                ? " · " + percentage(cluster.model_fraction)
                : "");

            clusterHead.append(title, stats);
            section.appendChild(clusterHead);

            const verb = clusterVerbs.get(cluster.cluster_id);
            const explanation = document.createElement("p");
            explanation.className = "cluster-text";
            explanation.textContent =
              verb?.text || "No cluster verbalization generated.";

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
                image.alt = "Heatmap for model " + model.iteration;

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
                const axiomDetails = document.createElement("details");
                const axiomSummary = document.createElement("summary");
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
        {:error, {:cannot_prepare_ui_assets, Exception.message(error)}}
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
          |> Enum.map(&copy_model_graphs(&1, run_id, assets_dir, html_dir))

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
      nil ->
        model

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
