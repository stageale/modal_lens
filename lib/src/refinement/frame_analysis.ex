defmodule Src.Core.FrameAnalysis do
  defstruct [
    :serial?,
    :reflexive?,
    :transitive?,
    :symmetric?,
    :euclidean?,
    :functional?,
    :total_functional?,
    dead_ends: [],                      #* violations of seriality
    missing_loops: [],                  #* violations of reflexivity
    missing_hulls: [],                  #* violations of transitivity
    antisymmetries: [],                 #* violations of symmetry
    missing_spans: [],                  #* violations of euclidity
    function_violations: MapSet.new(),
  ]

  def frame_axiom(r \\ "R", kind)

  def frame_axiom(r, :serial), do: "∀w. ∃v. #{r} w v"
  def frame_axiom(r, :reflexive), do: "∀w. #{r} w w"
  def frame_axiom(r, :transitive), do: "∀w v u. (#{r} w v ∧ #{r} v u) → #{r} w u"
  def frame_axiom(r, :symmetric), do: "∀w v. #{r} w v → #{r} v w"
  def frame_axiom(r, :euclidean), do: "∀w v u. (#{r} w v ∧ #{r} w u) → #{r} v u"
  def frame_axiom(r, :functional), do: "∀w. ∃v. (#{r} w v ∧ ¬∃u. #{r} w u ∧ v ≠ u)"

  def isabelle_axiom(name, formula) do
    """
    axiomatization where
    #{name}: "#{formula}"
    """
  end

  def check?(frame, axiom), do: violations(frame, axiom) == []

  def violations(frame, axiom) do
    elems = frame
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
        for u <- elems, v <- elems, w <- elems,
          binds.(u, v) and binds.(v, w) and not binds.(u, w),
          do: {u, v, w}

      :symmetric ->
        #? Revision of this measure
        for u <- elems, v <- elems,
          binds.(u, v) and not binds.(v, u),
          do: {u, v}

      :euclidean ->
        for u <- elems, v <- elems, w <- elems,
          binds.(u, v) and binds.(u, w) and not binds.(v, w),
          do: {u, v, w}

      :functional ->
        #* check partial functionality
        for u <- elems, v <- elems, w <- elems,
          binds.(u, v) and binds.(u, w) and v != w,
          do: {u, v, w}

      :total_functional ->
        #* check total functionality
        for u <- elems, v <- elems,
          binds.(u, v),
          w <- elems,
          binds.(u, w) and v != w,
          do: {u, v, w}
    end
  end
end
