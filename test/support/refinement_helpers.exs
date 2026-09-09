defmodule Src.Refinement.TestSupport do
  @moduledoc """
  Shared data and process fixtures for refinement tests.

  The shell fixtures exercise the real Elixir orchestration without running
  Isabelle, graph analysis or an LLM. Their output is synthetic test data.
  Tests changing PATH or the Isabelle environment must run synchronously.
  """

  alias Src.Execution.Run

  @doc "Builds a complete candidate, including negative relation cells and valuations."
  @spec candidate(keyword()) :: map()
  def candidate(opts \\ []) do
    size = Keyword.get(opts, :size, 2)
    ids = Enum.map(1..size, &"u#{&1}")
    inside = Keyword.get(opts, :cluster_support, 0.75)
    outside = Keyword.get(opts, :outside_support, 0.25)

    %{
      "schema" => "modal-lens/refinement-candidate",
      "schema_version" => "1.0",
      "candidate_id" => Keyword.get(opts, :id, "refinement-cluster-0-pattern-1"),
      "kind" => "exact_induced_graphlet_exclusion",
      "status" => "candidate",
      "origin" => %{
        "pattern_id" => "cluster-0-pattern-1",
        "cluster_id" => 0,
        "rank" => 1,
        "cluster_support" => inside,
        "outside_support" => outside,
        "contrast" => inside - outside
      },
      "occurrence" => %{
        "size" => size,
        "pairwise_distinct" => true,
        "worlds" =>
          Enum.map(ids, &%{"id" => &1, "valuations" => %{"p" => &1 == "u1", "q" => false}}),
        "relation_cells" =>
          for source <- ids, target <- ids do
            %{
              "source" => source,
              "target" => target,
              "relation" => "R",
              "holds" => source == "u1" and target == "u2"
            }
          end
      },
      "refinement" => %{
        "rule" => "exclude_exact_induced_occurrence",
        "operator" => "not",
        "operand" => "occurrence"
      }
    }
  end

  @doc "Creates an isolated workspace and removes it after the test."
  @spec workspace() :: map()
  def workspace do
    root =
      Path.join(System.tmp_dir!(), "modal_lens_refinement_#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)
    theory = Path.join(root, "Base.thy")
    File.write!(theory, "theory Base\nimports Main\nbegin\nend\n")
    %{root: root, theory: theory}
  end

  @doc "Installs deterministic executable fixtures and prepares a one-model pipeline run."
  @spec pipeline_context() :: map()
  def pipeline_context do
    context = workspace()
    isabelle = write_executable(context.root, "isabelle", isabelle_script())
    uv = write_executable(context.root, "uv", uv_script())
    write_candidates(context, [candidate()])

    previous = Map.new(["PATH", "MODAL_LENS_ISABELLE_BIN"], &{&1, System.get_env(&1)})

    ExUnit.Callbacks.on_exit(fn ->
      Enum.each(previous, fn
        {name, nil} -> System.delete_env(name)
        {name, value} -> System.put_env(name, value)
      end)
    end)

    System.put_env("MODAL_LENS_ISABELLE_BIN", isabelle)
    System.put_env("PATH", context.root <> ":" <> (previous["PATH"] || ""))

    {:ok, run} =
      Run.new("refinement-test", Path.join(context.root, "out"), %{
        max_models: 1,
        model_logic: :sdl,
        relation: "R",
        atoms: ["p", "q"],
        auto_atoms?: false,
        render_graph?: false,
        verbalize?: false,
        project_root: context.root,
        uv_executable: uv
      })

    Map.merge(context, %{run: run, isabelle: isabelle, uv: uv})
  end

  @doc "Sets the candidates returned by the synthetic graph-analysis process."
  @spec write_candidates(map(), [map()]) :: :ok
  def write_candidates(context, candidates) do
    report = %{
      "schema" => "modal-lens/analysis-report",
      "schema_version" => "1.1",
      "analysis" => %{
        "model_count" => 1,
        "cluster_count" => 1,
        "reported_pattern_count" => 0,
        "refinement_candidate_count" => length(candidates)
      },
      "clusters" => [
        %{
          "cluster_id" => 0,
          "model_count" => 1,
          "model_fraction" => 1.0,
          "model_indices" => [0],
          "characteristic_patterns" => [],
          "representative_model" => %{"graph_index" => 0}
        }
      ],
      "highlights" => [],
      "refinement_candidates" => candidates
    }

    File.write!(Path.join(context.root, "analysis-fixture.json"), Jason.encode!(report))
  end

  @doc "Returns the recorded calls to a synthetic backend."
  @spec calls(map(), String.t()) :: [String.t()]
  def calls(context, backend) do
    case File.read(Path.join(context.root, "#{backend}.calls")) do
      {:ok, text} -> String.split(text, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end

  @spec write_executable(String.t(), String.t(), String.t()) :: String.t()
  defp write_executable(root, name, body) do
    path = Path.join(root, name)
    File.write!(path, "#!/bin/sh\nset -eu\n" <> body)
    File.chmod!(path, 0o755)
    path
  end

  @spec isabelle_script() :: String.t()
  defp isabelle_script do
    ~S"""
    root=$(dirname "$0")
    printf '%s\n' "$*" >> "$root/isabelle.calls"
    if [ -f "$root/fail-isabelle" ]; then
      printf 'synthetic Isabelle failure\n'
      exit 7
    fi
    if [ -f "$root/empty-models" ]; then
      printf 'Nitpick found no counterexample\n'
      exit 0
    fi
    if [ -f "$root/empty-refined" ]; then
      case "$*" in *"_Refined_"*) printf 'Nitpick found no counterexample\n'; exit 0;; esac
    fi
    cat <<'OUT'
    Nitpick found a counterexample for card i = 2:
    w = i⇩1
    R = (i⇩1, i⇩2) := True
    p = i⇩1 := True, i⇩2 := False
    q = i⇩1 := False, i⇩2 := False
    OUT
    """
  end

  @spec uv_script() :: String.t()
  defp uv_script do
    ~S"""
    root=$(dirname "$0")
    case "$4" in
      graph_ml.launcher)
        shift 4
        theory=''
        output=''
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --theory) theory=$2; shift 2;;
            --output) output=$2; shift 2;;
            *) shift;;
          esac
        done
        printf '%s\n' "$theory" >> "$root/graph.calls"
        if [ -f "$root/fail-graph" ]; then exit 8; fi
        cp "$root/analysis-fixture.json" "$output"
        printf '{"schema":"modal-lens/graph-analysis-result","schema_version":"1.0","status":"completed","report_path":"%s"}\n' "$output"
        ;;
      verbalization.launcher)
        request=$5
        printf '%s\n' "$request" >> "$root/verbalization.calls"
        test -f "$root/out/refinement.json"
        if [ -f "$root/fail-verbalization" ]; then exit 9; fi
        output=$(dirname "$request")
        printf '{"schema":"modal-lens/refinement-summary","schema_version":"1.0","overview":"Synthetic summary","overview_evidence":["refinement.stop_reason"],"round_summaries":[],"limitations":["Synthetic test data"]}\n' > "$output/summary.json"
        printf '# Refinement Summary\n' > "$output/summary.md"
        printf '{}\n' > "$output/raw_output.txt"
        printf '{}\n' > "$output/provenance.json"
        printf '{"status":"completed","artifacts":{"summary_json":"%s/summary.json","summary_markdown":"%s/summary.md","raw_output":"%s/raw_output.txt","provenance":"%s/provenance.json"}}\n' "$output" "$output" "$output" "$output"
        ;;
      *) exit 64;;
    esac
    """
  end
end
