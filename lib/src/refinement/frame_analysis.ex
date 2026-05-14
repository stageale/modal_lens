defmodule Src.Core.FrameAnalysis do
  defstruct [
    :serial?,
    :reflexive?,
    :transitive?,
    :symmetric?,
    :euclidean?,
    :functional?,
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
  def frame_axiom(r, :connected), do: "connected" #* Solve this by algorithmic path finding

  def isabelle_axiom(name, formula) do
    """
    axiomatization where
    #{name}: "#{formula}"
    """
  end

  def check?(frame, axiom) do
    elems = frame
        |> List.flatten()
        |> MapSet.new()

    edge_set = MapSet.new(frame)

    case axiom do
      :serial ->
        #TODO: Implement seriality check
        Enum.all?(elems, fn u ->
          Enum.any?(elems, fn v ->
            MapSet.member?(edge_set, {u, v})
          end)
        end)

      :reflexive ->
        #TODO: Implement reflexivity check
        Enum.all?(elems, fn u -> MapSet.member?(edge_set, {u, u}) end)

      :transitive ->
        #TODO: Implement transitivity check
        Enum.all?(elems, fn u ->
          Enum.all?(elems, fn v ->
            Enum.all?(elems, fn w ->
              not (MapSet.member?(edge_set, {u, v}) and MapSet.member?(edge_set, {v, w}))
              or MapSet.member?(edge_set, {u, w})
            end)
          end)
        end)

      :symmetric ->
        #TODO: Implement symmetry check
        Enum.all?(elems, fn u ->
          Enum.all?(elems, fn v ->
            not MapSet.member?(edge_set, {u, v}) or MapSet.member?(edge_set, {v, u})
          end)
        end)

      :euclidean ->
        #TODO: Implement euclidean check
        Enum.all?(elems, fn u ->
          Enum.all?(elems, fn v ->
            Enum.all?(elems, fn w ->
              not (MapSet.member?(edge_set, {u, v}) and MapSet.member?(edge_set, {u, w})) or MapSet.member?(edge_set, {v, w})
            end)
          end)
        end)

      :functional ->
        #TODO: Implement functionality check
        Enum.all?(elems, fn u ->
          Enum.any?(elems, fn v ->
            #MapSet.member?()
            nil
          end)
        end)
    end
  end
end
