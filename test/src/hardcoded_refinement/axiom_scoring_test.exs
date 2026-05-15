defmodule Src.HardcodedRefinement.AxiomScoringTest do
  use ExUnit.Case, async: true

  alias Src.HardcodedRefinement.AxiomScoring
  alias Src.HardcodedRefinement.FrameAnalysis
  alias Src.HardcodedRefinement.FrameStats

  describe "metrics/3" do
    test "computes violation densities with all-pairs euclidean support and pair-based functionality" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [:a, :b],
        antisymmetries: [{:a, :b}, {:a, :c}, {:b, :c}],
        missing_hulls: [],
        missing_spans: [
          {:a, :b, :b},
          {:a, :c, :b}
        ],
        function_violations: MapSet.new([:a])
      }

      metrics =
        AxiomScoring.metrics(
          analysis,
          stats,
          euclidean_mode: :all_pairs,
          functional_mode: :pairs
        )

      serial = find_metric(metrics, :serial)
      reflexive = find_metric(metrics, :reflexive)
      symmetric = find_metric(metrics, :symmetric)
      transitive = find_metric(metrics, :transitive)
      euclidean = find_metric(metrics, :euclidean)
      functional = find_metric(metrics, :functional)

      assert serial.violations == 0
      assert serial.support == 3
      assert_in_delta serial.density, 0.0, 1.0e-12

      assert reflexive.violations == 2
      assert reflexive.support == 3
      assert_in_delta reflexive.density, 2 / 3, 1.0e-12

      assert symmetric.violations == 3
      assert symmetric.support == 3
      assert_in_delta symmetric.density, 1.0, 1.0e-12

      assert transitive.violations == 0
      assert transitive.support == 4
      assert_in_delta transitive.density, 0.0, 1.0e-12

      assert euclidean.violations == 2
      assert euclidean.support == 6
      assert_in_delta euclidean.density, 2 / 6, 1.0e-12

      assert functional.violations == 2
      assert functional.support == 6
      assert_in_delta functional.density, 2 / 6, 1.0e-12
    end

    test "uses distinct-pairs support for euclideanness when requested" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [],
        antisymmetries: [],
        missing_hulls: [],
        missing_spans: [
          {:a, :b, :b},
          {:a, :c, :b}
        ],
        function_violations: MapSet.new()
      }

      metrics =
        AxiomScoring.metrics(
          analysis,
          stats,
          euclidean_mode: :distinct_pairs,
          functional_mode: :pairs
        )

      euclidean = find_metric(metrics, :euclidean)

      assert euclidean.violations == 2
      assert euclidean.support == 2
      assert_in_delta euclidean.density, 1.0, 1.0e-12
    end

    test "uses excess-based functionality when requested" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [],
        antisymmetries: [],
        missing_hulls: [],
        missing_spans: [],
        function_violations: MapSet.new([:a])
      }

      metrics =
        AxiomScoring.metrics(
          analysis,
          stats,
          functional_mode: :excess
        )

      functional = find_metric(metrics, :functional)

      assert functional.violations == 1
      assert functional.support == 6
      assert_in_delta functional.density, 1 / 6, 1.0e-12
    end

    test "uses analysis-world-based functionality when requested" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      stats = FrameStats.from_edges(worlds, edges)

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [],
        antisymmetries: [],
        missing_hulls: [],
        missing_spans: [],
        function_violations: MapSet.new([:a])
      }

      metrics =
        AxiomScoring.metrics(
          analysis,
          stats,
          functional_mode: :analysis_worlds
        )

      functional = find_metric(metrics, :functional)

      assert functional.violations == 1
      assert functional.support == 3
      assert_in_delta functional.density, 1 / 3, 1.0e-12
    end
  end

  describe "ranked_suggestions/4" do
    test "returns scored metrics sorted by descending score" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [:a, :b],
        antisymmetries: [{:a, :b}, {:a, :c}, {:b, :c}],
        missing_hulls: [],
        missing_spans: [
          {:a, :b, :b},
          {:a, :c, :b}
        ],
        function_violations: MapSet.new([:a])
      }

      ranking =
        AxiomScoring.ranked_suggestions(
          analysis,
          worlds,
          edges,
          euclidean_mode: :all_pairs,
          functional_mode: :pairs
        )

      scores = Enum.map(ranking, & &1.score)

      assert scores == Enum.sort(scores, :desc)

      assert hd(ranking).axiom == :symmetric

      symmetric = find_metric(ranking, :symmetric)
      reflexive = find_metric(ranking, :reflexive)
      euclidean = find_metric(ranking, :euclidean)
      functional = find_metric(ranking, :functional)

      assert_in_delta symmetric.score, 1.0 * 1.0 * :math.log(1.0 + 3), 1.0e-12
      assert_in_delta reflexive.score, 1.0 * (2 / 3) * :math.log(1.0 + 3), 1.0e-12
      assert_in_delta euclidean.score, 1.3 * (2 / 6) * :math.log(1.0 + 6), 1.0e-12
      assert_in_delta functional.score, 1.2 * (2 / 6) * :math.log(1.0 + 6), 1.0e-12
    end

    test "accepts custom weights" do
      worlds = [:a, :b, :c]

      edges = [
        {:a, :b},
        {:a, :c},
        {:b, :c},
        {:c, :c}
      ]

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [:a, :b],
        antisymmetries: [{:a, :b}, {:a, :c}, {:b, :c}],
        missing_hulls: [],
        missing_spans: [
          {:a, :b, :b},
          {:a, :c, :b}
        ],
        function_violations: MapSet.new([:a])
      }

      ranking =
        AxiomScoring.ranked_suggestions(
          analysis,
          worlds,
          edges,
          weights: %{
            serial: 1.0,
            reflexive: 10.0,
            symmetric: 1.0,
            transitive: 1.0,
            euclidean: 1.0,
            functional: 1.0
          }
        )

      assert hd(ranking).axiom == :reflexive
    end
  end

  describe "zero support" do
    test "density and score are zero when support is zero" do
      worlds = []
      edges = []

      analysis = %FrameAnalysis{
        dead_ends: [],
        missing_loops: [],
        antisymmetries: [],
        missing_hulls: [],
        missing_spans: [],
        function_violations: MapSet.new()
      }

      ranking =
        AxiomScoring.ranked_suggestions(
          analysis,
          worlds,
          edges
        )

      assert Enum.all?(ranking, fn metric ->
               metric.support == 0
             end)

      assert Enum.all?(ranking, fn metric ->
               metric.density == 0.0
             end)

      assert Enum.all?(ranking, fn metric ->
               metric.score == 0.0
             end)
    end
  end

  defp find_metric(metrics, axiom) do
    Enum.find(metrics, fn metric -> metric.axiom == axiom end)
  end
end
