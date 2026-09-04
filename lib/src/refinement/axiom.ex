defmodule Src.Refinement.Axiom do
  @moduledoc """
  Renders structural refinement candidates as Isabelle/HOL axioms.

  A refinement candidate describes the negation of an exact induced graphlet
  occurrence. The module translates this neutral description into Isabelle
  syntax without assigning a modal frame property or interpreting the candidate
  as a validated logical principle

  Unlike a single-model-blocking axiom, the generated occurrence formula does
  not contain domain closure. It therefore describes a possible induced
  substructure inside a larger model.

  Assume a pattern `P` mined from a cluster of countermodels for an input
  theory. The generated refinement axiom negates the existential occurrence
  of `P` as an exact induced substructure.

  Consequently, the axiom excludes every model containing `P`, not the cluster
  as such. It excludes all currently enumerated member of the cluster only
  when the measured cluster support of `P` is `1.0`.
  """

  @typedoc "A JSON-decoded structural refinement candidate."
  @type candidate :: %{required(String.t()) => term()}

  @typedoc "An Isabelle/HOL formula fragment."
  @type formula :: String.t()

  @typedoc "An Isabelle-compatible identifier."
  @type id :: String.t()

  @typedoc "An option controlling axiom rendering."
  @type option :: {:name, String.t()}

  @typedoc "Options controlling axiom rendering."
  @type options :: [option()]

  @typedoc "A validated world from the occurrence specification."
  @type world :: %{
    id: id(),
    valuations: %{required(id()) => boolean()}
  }

  @typedoc "A validated cell of the induced relation matrix."
  @type relation_cell :: %{
    source: id(),
    target: id(),
    relation: id(),
    holds: boolean()
  }

  @typedoc "The validated internal representation of a candidate."
  @type normalized_candidate :: %{
    candidate_id: String.t(),
    worlds: [world()],
    relation_cells: [relation_cell()]
  }

  @schema "modal-lens/refinement-candidate"
  @schema_version "1.0"
  @kind "exact_induced_graphlet_exclusion"

  @isabelle_not ~S(\<not>)
  @isabelle_exists ~S(\<exists>)
  @isabelle_and ~S(\<and>)


  @doc """
  Renders the exact existential occurrence described by `candidate`.
  The formula contains pairwise distinct world representatives, the complete
  internal relation matrix, and complete valuations over the supplied
  proposition signature. It deliberately contains no domain-closure clause.

  Raises `ArgumentError` when the candidate violates the expected schema.
  """
  @spec occurrence_formula(candidate()) :: formula()
  def occurrence_formula(candidate) do
    candidate
    |> normalize_candidate!()
    |> render_occurrence()
  end

  @doc """
  Renders the structural refinement formula for `candidate`.

  The refinement is the negation of the exact induced graphlet occurrence. The
  result remains a candidate and is not classified as a modal frame condition.

  Raises `ArgumentError` when the candidate violates the expected schema.
  """
  @spec refinement_formula(candidate()) :: formula()
  def refinement_formula(candidate) do
    candidate
    |> normalize_candidate!()
    |> render_refinement()
  end

  @doc """
  Wraps the refinement formula in an Isabelle axiomatization.

  The optional `:name` overrides the axiom name derived from the candidate ID.
  The name is sanitized before being inserted into Isabelle syntax.

  Raises `ArgumentError` when the candidate or requested name is invalid.
  """
  @spec refinement_axiom(candidate()) :: String.t()
  @spec refinement_axiom(candidate(), options()) :: String.t()
  def refinement_axiom(candidate, opts \\ []) do
    normalized = normalize_candidate!(candidate)

    axiom_name =
      opts
      |> Keyword.get(:name, normalized.candidate_id)
      |> sanitize_name()

    formula =
      normalized
      |> render_refinement()
      |> indent_continuation(4)

    """
    axiomatization where
      ax_#{axiom_name}: "#{formula}"
    """
    |> String.trim()
  end

  @spec normalize_candidate!(term()) :: normalized_candidate()
  defp normalize_candidate!(
    %{
      "schema" => @schema,
      "schema_version" => @schema_version,
      "candidate_id" => candidate_id,
      "kind" => @kind,
      "status" => "candidate",
      "origin" => origin,
      "occurrence" => occurrence,
      "refinement" => %{
        "rule" => "exclude_exact_induced_occurrence",
        "operator" => "not",
        "operand" => "occurrence"
      }
    }
  ) when is_binary(candidate_id) and is_map(origin) do
    if String.trim(candidate_id) == "" do
      raise ArgumentError, "refinement candidate ID must not be empty"
    end

    occurrence
    |> normalize_occurrence!()
    |> Map.put(:candidate_id, candidate_id)
  end

  defp normalize_candidate!(_candidate) do
    raise ArgumentError,
          "expected a modal-lens/refinement-candidate with schema version 1.0"
  end

  @spec normalize_occurrence!(term()) :: %{worlds: [world()], relation_cells: [relation_cell()]}
  defp normalize_occurrence!(
    %{
      "size" => size,
      "pairwise_distinct" => true,
      "worlds" => raw_worlds,
      "relation_cells" => raw_cells
    }
  )
  when is_integer(size) and size > 0 and is_list(raw_worlds) and is_list(raw_cells) do
    if length(raw_worlds) != size do
      raise ArgumentError,
            "occurrence world count must equal its declared size"
    end

    if length(raw_cells) != size * size do
      raise ArgumentError,
            "occurrence must contain exactly size² relation cells"
    end

    worlds = Enum.map(raw_worlds, &normalize_world!/1)
    world_ids = Enum.map(worlds, & &1.id)
    validate_unique_worlds!(world_ids)
    validate_uniform_signature!(worlds)

    relation_cells =
      Enum.map(raw_cells, &normalize_relation_cell!(&1, world_ids))

    validate_relation_matrix!(relation_cells, world_ids)

    %{
      worlds: worlds,
      relation_cells:
        sort_relation_cells(relation_cells, world_ids)
    }
  end


  defp normalize_occurrence!(_occurrence) do
    raise ArgumentError,
          "candidate occurrence must describe pairwise distinct worlds"
  end

  @spec normalize_world!(term()) :: world()
  defp normalize_world!(
    %{
      "id" => world_id,
      "valuations" => valuations
    }
  )
  when is_binary(world_id) and is_map(valuations) do
    validate_identifier!(world_id, "world")

    normalized_valuations =
      Map.new(valuations, fn
        {atom, truth_value} when is_binary(atom) and is_boolean(truth_value) ->
          validate_identifier!(atom, "proposition")
          {atom, truth_value}
        {atom, truth_value} ->
          raise ArgumentError,
                "invalid valuation #{inspect(atom)} => " <>
                  inspect(truth_value)
      end)

    %{
      id: world_id,
      valuations: normalized_valuations
    }
  end

  defp normalize_world!(_world) do
    raise ArgumentError,
          "every occurrence world must contain an ID and valuations"
  end

  @spec validate_unique_worlds!([id()]) :: :ok
  defp validate_unique_worlds!(world_ids) do
    if length(Enum.uniq(world_ids)) != length(world_ids) do
      raise ArgumentError,
            "occurrence world IDs must be unique"
    end

    :ok
  end

  @spec validate_uniform_signature!([world()]) :: :ok
  defp validate_uniform_signature!(worlds) do
    signatures =
      Enum.map(worlds, fn world ->
        world.valuations
        |> Map.keys()
        |> Enum.sort()
      end)

    if length(Enum.uniq(signatures)) != 1 do
      raise ArgumentError,
            "every occurrence world must use the same proposition signature"
    end

    :ok
  end

  @spec normalize_relation_cell!(term(), [id()]) :: relation_cell()
  defp normalize_relation_cell!(
    %{
      "source" => source,
      "target" => target,
      "relation" => relation,
      "holds" => holds
    },
    world_ids
  )
  when is_binary(source) and is_binary(target) and
        is_binary(relation) and is_boolean(holds) do
    validate_identifier!(source, "source world")
    validate_identifier!(target, "target world")
    validate_identifier!(relation, "relation")

    unless source in world_ids do
      raise ArgumentError,
            "unknown relation source #{inspect(source)}"
    end

    unless target in world_ids do
      raise ArgumentError,
            "unknown relation target #{inspect(target)}"
    end

    %{
      source: source,
      target: target,
      relation: relation,
      holds: holds
    }
  end

  defp normalize_relation_cell!(_cell, _world_ids) do
    raise ArgumentError,
          "invalid induced-relation cell"
  end

  @spec validate_relation_matrix!([relation_cell()], [id()]) :: :ok
  defp validate_relation_matrix!(relation_cells, world_ids) do
    relations =
      relation_cells
      |> Enum.map(& &1.relation)
      |> Enum.uniq()

    if length(relations) != 1 do
      raise ArgumentError,
            "the current refinement contract requires exactly one relation"
    end

    actual_pairs =
      Enum.map(
        relation_cells,
        &{&1.source, &1.target}
      )

    if length(Enum.uniq(actual_pairs)) != length(actual_pairs) do
      raise ArgumentError,
            "the induced relation matrix contains duplicate cells"
    end

    expected_pairs =
      for source <- world_ids,
          target <- world_ids do
            {source, target}
      end

    if MapSet.new(actual_pairs) != MapSet.new(expected_pairs) do
      raise ArgumentError,
            "the induced relation matrix is incomplete"
    end

    :ok
  end

  @spec sort_relation_cells([relation_cell()], [id()]) :: [relation_cell()]
  defp sort_relation_cells(relation_cells, world_ids) do
    positions =
      world_ids
      |> Enum.with_index()
      |> Map.new()

    Enum.sort_by(relation_cells, fn cell ->
      {
        Map.fetch!(positions, cell.source),
        Map.fetch!(positions, cell.target)
      }
    end)
  end

  @spec render_occurrence(normalized_candidate()) :: formula()
  defp render_occurrence(candidate) do
    world_ids =
      Enum.map(candidate.worlds, & &1.id)

    clauses =
      [distinct_clause(world_ids)] ++
        relation_clauses(candidate.relation_cells) ++
        valuation_clauses(candidate.worlds)

    body =
      Enum.join(clauses, " #{@isabelle_and}\n  ")

    """
    #{@isabelle_exists}#{Enum.join(world_ids, " ")}.
      #{body}
    """
    |> String.trim()
  end

  @spec render_refinement(normalized_candidate()) :: formula()
  defp render_refinement(candidate) do
    occurrence =
      candidate
      |> render_occurrence()
      |> indent(2)

    """
    #{@isabelle_not} (
    #{occurrence}
    )
    """
    |> String.trim()
  end

  @spec distinct_clause([id()]) :: formula()
  defp distinct_clause(world_ids) do
    "distinct [#{Enum.join(world_ids, ", ")}]"
  end

  @spec relation_clauses([relation_cell()]) :: [formula()]
  defp relation_clauses(relation_cells) do
    Enum.map(relation_cells, fn cell ->
      application =
        "#{cell.relation} #{cell.source} #{cell.target}"

      if cell.holds do
        application
      else
        "#{@isabelle_not} (#{application})"
      end
    end)
  end

  @spec valuation_clauses([world()]) :: [formula()]
  defp valuation_clauses(worlds) do
    Enum.flat_map(worlds, fn world ->
      world.valuations
      |> Enum.sort_by(fn {atom, _truth_value} ->
        atom
      end)
      |> Enum.map(fn {atom, truth_value} ->
        application = "#{atom} #{world.id}"

        if truth_value do
          application
        else
          "#{@isabelle_not} (#{application})"
        end
      end)
    end)
  end

  @spec validate_identifier!(String.t(), String.t()) :: :ok
  defp validate_identifier!(identifier, role) do
    unless Regex.match?(~r/^[A-Za-z][A-Za-z0-9_']*$/, identifier) do
      raise ArgumentError,
            "#{role} is not an Isabelle-compatible identifier: " <>
              inspect(identifier)
    end

    :ok
  end

  @spec sanitize_name(String.t()) :: id()
  defp sanitize_name(name) when is_binary(name) do
    stem =
      name
      |> String.trim()
      |> then(&Regex.replace(~r/[^A-Za-z0-9_]+/, &1, "_"))
      |> then(&Regex.replace(~r/_+/, &1, "_"))
      |> String.trim("_")

    cond do
      stem == "" ->
        raise ArgumentError,
              "refinement axiom name must not be empty"

      Regex.match?(~r/^\d/, stem) ->
        "refinement_#{stem}"

      true ->
        stem
    end
  end

  defp sanitize_name(name) do
    raise ArgumentError,
          "refinement axiom name must be a string, got: " <>
            inspect(name)
  end

  @spec indent(String.t(), non_neg_integer()) :: String.t()
  defp indent(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", &(prefix <> &1))
  end

  @spec indent_continuation(String.t(), non_neg_integer()) :: String.t()
  defp indent_continuation(text, spaces) do
    prefix = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.with_index()
    |> Enum.map_join("\n", fn
      {line, 0} -> line
      {line, _index} -> prefix <> line
    end)
  end
end
