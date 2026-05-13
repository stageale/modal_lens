defmodule Src.Core.Axiom do
  alias Src.Core.Model

  def sanitize_name(name) when is_binary(name) do
    stem =
      name
      |> Regex.replace(~r/[^A-Za-z0-9_]+/, "_")
      |> Regex.replace(~r/_+/, "_")
      |> String.trim("_")

    cond do
      stem == "" ->
        "nitpick_model"

      Regex.match?(~r/^\d/, stem) ->
        "m_#{stem}"

      true ->
        stem
    end
  end

  def source_stem(%Model{source: nil}) do
    "nitpick_model"
  end

  def source_stem(%Model{source: source}) when is_binary(source) do
    source
    |> Path.basename()
    |> Path.rootname()
  end

  def exact_structure_formula(%Model{} = model, opts \\ []) do
    include_atoms = Keyword.get(opts, :include_atoms, true)
    include_initial = Keyword.get(opts, :include_initial, false)

    relation_clauses =
      for i <- 0..(model.cardinality - 1),
          j <- 0..(model.cardinality - 1) do
            wi = Model.world_name(model, i)
            wj = Model.world_name(model, j)
            atom = "(#{model.relation_name} #{wi} #{wj})"

            if MapSet.member?(model.edges, {i, j}) do
              atom
            else
              "¬#{atom}"
            end
          end
    valuation_clauses =
      if include_atoms do
        model.valuations
        |> Map.keys()
        |> Enum.sort()
        |> Enum.flat_map(fn pred ->
          vals = Map.fetch!(model.valuations, pred)

          vals
          |> Enum.with_index()
          |> Enum.map(fn {truth, i} ->
            atom = "(#{pred} #{Model.world_name(model, i)})"

            if truth do
              atom
            else
              "¬#{atom}"
            end
          end)
        end)
      else
        []
      end
    initial_clauses =
      if include_initial do
        ["w = #{Model.world_name(model, model.initial_world)}"]
      else
        []
      end

    and_clauses(initial_clauses ++ relation_clauses ++ valuation_clauses)
  end

  def blocking_axiom(%Model{} = model, opts \\ []) do
    name = Keyword.get(opts, :name, nil)
    include_atoms = Keyword.get(opts, :include_atoms, true)

    ax_name =
      (name || source_stem(model))
      |> sanitize_name()

    body = exact_structure_formula(model, include_atoms: include_atoms)

    ~s/(axiomatization where ax_#{ax_name}: "¬(\n #{body}\n)")/
  end

  defp and_clauses(clauses) do
    Enum.join(clauses, " ∧\n ")
  end
end
