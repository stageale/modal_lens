defmodule Src.Interface.Ui.Page do
  @moduledoc """
  Writes an interactive HTML view for a calculated UI session.
  """

  alias Src.Interface.Ui.Session
  alias Src.Interface.Ui.View

  @doc "Writes the session view to an HTML file."
  @spec write(Session.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def write(%Session{} = session, path) when is_binary(path) do
    path = Path.expand(path)

    with  :ok <- File.mkdir_p(Path.dirname(path)),
          :ok <- File.write(path, render(session)) do
            {:ok, path}
          end
  end

  defp encoded_variants(%Session{} = session) do
    session
    |> View.variants()
    |> Jason.encode!()
    |> String.replace("</", "<\\/")
  end

  @doc "Renders the complete HTML document."
  @spec render(Session.t()) :: String.t()
  def render(%Session{} = session) do
    variants = encoded_variants(session)

    """
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Axiom Refiner</title>
      <style>
        body {
          max-width: 1100px;
          margin: 0 auto;
          padding: 2rem;
          font-family: system-ui, sans-serif;
          background: #f6f7f9;
          color: #20242a;
        }

        header, main {
          background: white;
          padding: 1.5rem;
          border-radius: 12px;
          margin-bottom: 1rem;
        }

        select {
          min-width: 260px;
          padding: 0.5rem;
        }

        img {
          max-width: 100%;
        }

        pre {
          white-space: pre-wrap;
          background: #f1f3f5;
          padding: 1rem;
          border-radius: 8px;
        }
      </style>
    </head>
    <body>
      <header>
        <h1>Axiom Refiner</h1>

        <label>
          Calculated configuration
          <select id="variant"></select>
        </label>
      </header>

      <main>
        <h2 id="run-title"></h2>
        <div id="options"></div>
        <div id="graph"></div>

        <h3>Blocking axiom</h3>
        <pre id="axiom"></pre>

        <h3>Explanation</h3>
        <pre id="explanation"></pre>
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

          document.getElementById("run-title").textContent =
            variant.run.id + " · " + variant.run.status;

          document.getElementById("options").textContent =
            JSON.stringify(variant.options, null, 2);

          document.getElementById("axiom").textContent =
            result.blocking_axiom || "Not available";

          document.getElementById("explanation").textContent =
            result.llm_explanation || "Not available";

          const graph = document.getElementById("graph");
          graph.replaceChildren();

          if (result.graph_image_file) {
            const image = document.createElement("img");
            image.src = result.graph_image_file;
            image.alt = "Rendered countermodel";
            graph.appendChild(image);
          }
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

  defp prepare_variants(session, assets_dir, html_dir) do
    session
    |> View.variants()
    |> Enum.reduce_while({:ok, []}, fn variant, {:ok, variants} ->
      case copy_graph(variant, assets_dir, html_dir) do
        {:ok, prepared} -> {:cont, {:ok, [prepared | variants]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, variants} -> {:ok, Enum.reverse(variants)}
      error -> error
    end
  end

  defp copy_graph(%{result: %{graph_image_file: nil}} = variant, _assets, _html), do: {:ok, variant}

  defp copy_graph(%{result: %{graph_image_file: source}} = variant, assets_dir, html_dir) do
    target =
      Path.join(assets_dir, "#{variant.run.id}-#{Path.basename(source)}")

    with :ok <- File.cp(source, target) do
      relative_path =
        target
        |> Path.relative_to(html_dir)
        |> String.replace("\\", "/")

      {:ok, put_in(variant, [:result, :graph_image_file], relative_path)}
    end
  end

  @spec render([map()]) :: String.t()
  def render(variants) when is_list(variants) do
    variants =
      variants
      |> Jason.encode!()
      |> String.replace("</", "<\\/")

    """
    ...
    const variants = #{variants}
    ...
    """
  end
end
