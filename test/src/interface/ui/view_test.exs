defmodule Src.Interface.Ui.ViewTest do
  use ExUnit.Case, async: true

  alias Src.Execution.Options
  alias Src.Execution.Run
  alias Src.Interface.Ui.Session
  alias Src.Interface.Ui.View

  test "projects variants without internal model structs" do
    assert {:ok, options} = Options.new(verbalize?: false)
    assert {:ok, session} = Session.new("Example.thy")
    assert {:ok, run} = Run.new("variant-1", "/tmp/variant-1")

    result = %{
      status: :max_models_reached,
      model_count: 1,
      graph_analysis: %{cluster_count: 1},
      clusters: [
        %{
          cluster_id: 0,
          model_count: 1,
          model_fraction: 1.0,
          characteristic_patterns: [],
          models: [
            %{
              iteration: 1,
              cluster_id: 0,
              theory_name: "Example",
              model_summary: %{cardinality: 1},
              worlds: [0],
              warnings: [],
              graph_svg_file: "/tmp/model.svg",
              blocking_axiom: "not model",
              model: :internal
            }
          ]
        }
      ],
      cluster_verbs: []
    }

    session = Session.put_variant(session, options, run, result)
    assert [view] = View.variants(session)

    assert view.options[:verbalize?] == false
    assert view.run["id"] == "variant-1"
    assert view.result.status == :max_models_reached
    assert view.result.model_count == 1

    [model] = view.result.clusters |> hd() |> Map.fetch!(:models)
    refute Map.has_key?(model, :model)
    assert model.model_summary == %{cardinality: 1}
  end

  test "returns variants in execution order" do
    assert {:ok, session} = Session.new("Example.thy")
    assert {:ok, first_options} = Options.new(palette: :turbo)
    assert {:ok, second_options} = Options.new(palette: :magma)
    assert {:ok, first_run} = Run.new("first", "/tmp/first")
    assert {:ok, second_run} = Run.new("second", "/tmp/second")

    session =
      session
      |> Session.put_variant(first_options, first_run, %{})
      |> Session.put_variant(second_options, second_run, %{})

    assert Enum.map(View.variants(session), & &1.run["id"]) == ["first", "second"]
  end
end
