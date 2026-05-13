defmodule Src.Core.FrameAnalysis do
  defstruct [
    :serial?,
    :reflexive?,
    :transitive?,
    :symmetric?,
    :euclid?,
    :functional?,
    :connected?,
    dead_ends: [],                      #* violations of seriality
    missing_loops: [],                  #* violations of reflexivity
    missing_hulls: [],                  #* violations of transitivity
    antisymmetries: [],                 #* violations of symmetry
    missing_spans: [],                  #* violations of euclidity
    function_violations: MapSet.new(),
    components: []                      #* violations of connectivity
  ]
end
