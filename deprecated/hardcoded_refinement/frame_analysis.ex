defmodule Src.HardcodedRefinement.FrameAnalysis do
  alias Src.Core.Model

  defstruct [
    :serial?,
    :reflexive?,
    :transitive?,
    :symmetric?,
    :euclidean?,
    :functional?,
    # * violations of seriality
    dead_ends: [],
    # * violations of reflexivity
    missing_loops: [],
    # * violations of transitivity
    missing_hulls: [],
    # * violations of symmetry
    antisymmetries: [],
    # * violations of euclidity
    missing_spans: [],
    function_violations: MapSet.new()
  ]

  def frame_axiom(r \\ "R", kind)

  def frame_axiom(r, :serial), do: "∀w. ∃v. #{r} w v"
  def frame_axiom(r, :reflexive), do: "∀w. #{r} w w"
  def frame_axiom(r, :transitive), do: "∀w v u. (#{r} w v ∧ #{r} v u) → #{r} w u"
  def frame_axiom(r, :symmetric), do: "∀w v. #{r} w v → #{r} v w"
  def frame_axiom(r, :euclidean), do: "∀w v u. (#{r} w v ∧ #{r} w u) → #{r} v u"
  def frame_axiom(r, :functional), do: "∀w. ∃v. (#{r} w v ∧ ¬∃u. #{r} w u ∧ v ≠ u)"

  def worlds_for_model(%Model{} = model), do: Model.world_indices(model)

  def worlds_for_model(_model), do: []

  def analysis_from_model(%{} = model) do
    analysis_from_model(model, worlds_for_model(model))
  end

  def analysis_from_model(%{} = model, worlds) when is_list(worlds) do
    edge_set = MapSet.new(model.edges)
    has_edge? = fn u, v -> MapSet.member?(edge_set, {u, v}) end

    dead_ends =
      for u <- worlds,
          not Enum.any?(worlds, fn v -> has_edge?.(u, v) end),
          do: u

    missing_loops =
      for u <- worlds,
          not has_edge?.(u, u),
          do: u

    missing_hulls =
      for u <- worlds,
          v <- worlds,
          w <- worlds,
          has_edge?.(u, v) and has_edge?.(v, w) and not has_edge?.(u, w),
          do: {u, v, w}

    # Project convention: antisymmetries stores the missing reverse edge.
    antisymmetries =
      for u <- worlds,
          v <- worlds,
          has_edge?.(u, v) and not has_edge?.(v, u),
          do: {v, u}

    missing_spans =
      for u <- worlds,
          v <- worlds,
          w <- worlds,
          has_edge?.(u, v) and has_edge?.(u, w) and not has_edge?.(v, w),
          do: {u, v, w}

    function_violations =
      for u <- worlds,
          successors = Enum.filter(worlds, fn v -> has_edge?.(u, v) end),
          length(successors) != 1,
          into: MapSet.new(),
          do: {u, successors}

    %__MODULE__{
      serial?: dead_ends == [],
      reflexive?: missing_loops == [],
      transitive?: missing_hulls == [],
      symmetric?: antisymmetries == [],
      euclidean?: missing_spans == [],
      functional?: MapSet.size(function_violations) == 0,
      dead_ends: dead_ends,
      missing_loops: missing_loops,
      missing_hulls: missing_hulls,
      antisymmetries: antisymmetries,
      missing_spans: missing_spans,
      function_violations: function_violations
    }
  end

  def isabelle_axiom(name, formula) do
    """
    axiomatization where
    #{name}: "#{formula}"
    """
  end

  def check?(frame, axiom), do: violations(frame, axiom) == []

  def violations(frame, axiom) do
    elems =
      frame
      |> Enum.flat_map(fn {u, v} -> [u, v] end)
      |> MapSet.new()

    edge_set = MapSet.new(frame)

    binds = fn u, v -> MapSet.member?(edge_set, {u, v}) end

    case axiom do
      :serial ->
        for u <- elems,
            not Enum.any?(elems, fn v -> binds.(u, v) end),
            do: u

      :reflexive ->
        for u <- elems,
            not binds.(u, u),
            do: u

      :transitive ->
        for u <- elems,
            v <- elems,
            w <- elems,
            binds.(u, v) and binds.(v, w) and not binds.(u, w),
            do: {u, v, w}

      :symmetric ->
        # ? Revision of this measure
        for u <- elems, v <- elems, binds.(u, v) and not binds.(v, u), do: {v, u}

      :euclidean ->
        for u <- elems,
            v <- elems,
            w <- elems,
            binds.(u, v) and binds.(u, w) and not binds.(v, w),
            do: {u, v, w}

      :functional ->
        # * check total functionality
        for u <- elems,
            successors = Enum.filter(elems, fn v -> binds.(u, v) end),
            length(successors) != 1,
            do: {u, successors}
    end
  end
end
