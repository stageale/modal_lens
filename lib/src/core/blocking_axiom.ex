defmodule Src.Core.BlockingAxiom do
  @moduledoc """
  Generates Isabelle/HOL blocking axioms for finite Nitpick models.

  A blocking axiom excludes the isomorphism class of one parsed finite
  countermodel. It is a technical search constraint for countermodel
  enumeration and must not be interpreted as an additional deontic or
  legal axiom.

  The generated model description contains:

    * existentially quantified world representatives,
    * pairwise distinctness of those representatives,
    * a domain-closure condition,
    * the complete truth table of the parsed binary relation,
    * optionally the complete valuations of parsed unary predicates,
    * optionally the designated initial/actual world.

  Only structures represented by `Src.Core.Model` are blocked. Constants,
  functions, relations, or predicates not parsed into the model are not part
  of the blocking condition.
  """

  alias Src.Core.Model

  @default_world_prefix "u"
  @default_initial_world_constant "actual_world"

  @isabelle_not ~S(\<not>)
  @isabelle_exists ~S(\<exists>)
  @isabelle_forall ~S(\<forall>)
  @isabelle_and ~S(\<and>)
  @isabelle_or ~S(\<or>)

  @doc """
  Sanitizes a generated Isabelle theorem name.
  """
  def sanitize_name(name) when is_binary(name) do
    stem =
      ~r/[^A-Za-z0-9_]+/
      |> Regex.replace(name, "_")
      |> then(fn value ->
        Regex.replace(~r/_+/, value, "_")
      end)
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

  def source_stem(%Model{source: source})
      when is_binary(source) do
    source
    |> Path.basename()
    |> Path.rootname()
  end

  @doc """
  Produces an existential HOL formula describing the complete parsed model.

  Options:

    * `:include_atoms`
      Include all parsed unary predicate valuations. Defaults to `true`.

    * `:include_initial`
      Include the designated initial-world constant. Defaults to `false`.

      This should only be enabled when the parser has reliably recovered the
      designated world from Nitpick's output.

    * `:initial_world_constant`
      Isabelle constant denoting the designated world. Defaults to
      `"actual_world"`.

    * `:world_prefix`
      Prefix for generated bound variables. Defaults to `"u"`.

  Example shape:

      ∃u1 u2.
        distinct [u1, u2] ∧
        (∀x. x = u1 ∨ x = u2) ∧
        ¬ R u1 u1 ∧
        R u1 u2 ∧
        ...
  """
  def exact_structure_formula(
        %Model{} = model,
        opts \\ []
      ) do
    validate_model!(model)

    include_atoms =
      Keyword.get(opts, :include_atoms, true)

    include_initial =
      Keyword.get(opts, :include_initial, false)

    initial_world_constant =
      Keyword.get(
        opts,
        :initial_world_constant,
        @default_initial_world_constant
      )

    world_prefix =
      opts
      |> Keyword.get(
        :world_prefix,
        @default_world_prefix
      )
      |> sanitize_variable_prefix()

    worlds =
      world_variables(
        model.cardinality,
        world_prefix
      )

    structural_clauses =
      [
        distinct_clause(worlds),
        domain_closure_clause(worlds)
      ]

    initial_clauses =
      initial_world_clauses(
        model,
        worlds,
        include_initial,
        initial_world_constant
      )

    relation_clauses =
      relation_clauses(model, worlds)

    valuation_clauses =
      valuation_clauses(
        model,
        worlds,
        include_atoms
      )

    body =
      structural_clauses
      |> Kernel.++(initial_clauses)
      |> Kernel.++(relation_clauses)
      |> Kernel.++(valuation_clauses)
      |> and_clauses(2)

    quantified_worlds =
      Enum.join(worlds, " ")

    """
    #{@isabelle_exists}#{quantified_worlds}.
      #{body}
    """
    |> String.trim()
  end

  @doc """
  Produces the negation of the exact finite model description.
  """
  def blocking_formula(
        %Model{} = model,
        opts \\ []
      ) do
    model_formula =
      exact_structure_formula(model, opts)

    """
    #{@isabelle_not}(
      #{indent(model_formula, 2)}
    )
    """
    |> String.trim()
  end

  @doc """
  Wraps the blocking formula as a named Isabelle axiom.

  Existing callers using only `:name` and `:include_atoms` remain compatible.
  """
  def blocking_axiom(
        %Model{} = model,
        opts \\ []
      ) do
    axiom_name =
      opts
      |> Keyword.get(:name, source_stem(model))
      |> sanitize_name()

    formula =
      model
      |> blocking_formula(opts)
      |> indent_continuation(2)

    """
    axiomatization where
      ax_#{axiom_name}: "#{formula}"
    """
    |> String.trim()
  end

  defp world_variables(
         cardinality,
         prefix
       ) do
    for index <- 1..cardinality do
      "#{prefix}#{index}"
    end
  end

  defp distinct_clause(worlds) do
    "distinct [#{Enum.join(worlds, ", ")}]"
  end

  defp domain_closure_clause(worlds) do
    alternatives =
      worlds
      |> Enum.map_join(
        " #{@isabelle_or} ",
        fn world ->
          "x = #{world}"
        end
      )

    "(#{@isabelle_forall}x. #{alternatives})"
  end

  defp relation_clauses(
         %Model{} = model,
         worlds
       ) do
    for source_index <-
          0..(model.cardinality - 1),
        target_index <-
          0..(model.cardinality - 1) do
      source_world =
        Enum.at(worlds, source_index)

      target_world =
        Enum.at(worlds, target_index)

      proposition =
        "(#{model.relation_name} " <>
          "#{source_world} #{target_world})"

      truth =
        MapSet.member?(
          model.edges,
          {source_index, target_index}
        )

      literal(proposition, truth)
    end
  end

  defp valuation_clauses(
         _model,
         _worlds,
         false
       ) do
    []
  end

  defp valuation_clauses(
         %Model{} = model,
         worlds,
         true
       ) do
    model.valuations
    |> Enum.sort_by(fn {predicate, _values} ->
      predicate
    end)
    |> Enum.flat_map(fn {predicate, values} ->
      values
      |> Enum.with_index()
      |> Enum.map(fn {truth, world_index} ->
        world =
          Enum.at(worlds, world_index)

        proposition =
          "(#{predicate} #{world})"

        literal(proposition, truth)
      end)
    end)
  end

  defp initial_world_clauses(
         _model,
         _worlds,
         false,
         _constant
       ) do
    []
  end

  defp initial_world_clauses(
         %Model{} = model,
         worlds,
         true,
         initial_world_constant
       ) do
    validate_isabelle_identifier!(
      initial_world_constant,
      :initial_world_constant
    )

    designated_world =
      Enum.at(
        worlds,
        model.initial_world
      )

    [
      "(#{initial_world_constant} = " <>
        "#{designated_world})"
    ]
  end

  defp literal(proposition, true) do
    proposition
  end

  defp literal(proposition, false) do
    "#{@isabelle_not}#{proposition}"
  end

  defp and_clauses(
         clauses,
         indentation
       ) do
    separator =
      " #{@isabelle_and}\n" <>
        String.duplicate(
          " ",
          indentation
        )

    Enum.join(clauses, separator)
  end

  defp indent(
         text,
         spaces
       ) do
    prefix =
      String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join(
      "\n",
      fn line ->
        prefix <> line
      end
    )
  end

  defp indent_continuation(
         text,
         spaces
       ) do
    prefix =
      String.duplicate(" ", spaces)

    case String.split(text, "\n") do
      [] ->
        text

      [first | rest] ->
        [first | Enum.map(rest, &(prefix <> &1))]
        |> Enum.join("\n")
    end
  end

  defp sanitize_variable_prefix(prefix)
       when is_binary(prefix) do
    sanitized =
      prefix
      |> sanitize_name()
      |> String.trim_leading("m_")

    validate_isabelle_identifier!(
      sanitized,
      :world_prefix
    )

    sanitized
  end

  defp validate_model!(
         %Model{
           cardinality: cardinality
         } = model
       )
       when is_integer(cardinality) and
              cardinality > 0 do
    validate_initial_world!(model)
    validate_valuations!(model)
    validate_relation_name!(model)

    :ok
  end

  defp validate_model!(%Model{} = model) do
    raise ArgumentError,
          "blocking axioms require a positive finite cardinality, " <>
            "got: #{inspect(model.cardinality)}"
  end

  defp validate_initial_world!(%Model{
         cardinality: cardinality,
         initial_world: initial_world
       })
       when is_integer(initial_world) and
              initial_world >= 0 and
              initial_world < cardinality do
    :ok
  end

  defp validate_initial_world!(%Model{} = model) do
    raise ArgumentError,
          "initial world #{inspect(model.initial_world)} " <>
            "is outside cardinality #{inspect(model.cardinality)}"
  end

  defp validate_valuations!(%Model{} = model) do
    Enum.each(
      model.valuations,
      fn {predicate, values} ->
        validate_isabelle_identifier!(
          predicate,
          :predicate
        )

        unless is_list(values) and
                 length(values) ==
                   model.cardinality and
                 Enum.all?(
                   values,
                   &is_boolean/1
                 ) do
          raise ArgumentError,
                "valuation #{inspect(predicate)} must contain " <>
                  "exactly #{model.cardinality} Boolean values, " <>
                  "got: #{inspect(values)}"
        end
      end
    )
  end

  defp validate_relation_name!(%Model{
         relation_name: relation_name
       }) do
    validate_isabelle_identifier!(
      relation_name,
      :relation
    )
  end

  defp validate_isabelle_identifier!(
         identifier,
         kind
       )
       when is_binary(identifier) do
    if Regex.match?(
         ~r/^[A-Za-z][A-Za-z0-9_'.?]*$/,
         identifier
       ) do
      :ok
    else
      raise ArgumentError,
            "invalid Isabelle #{kind} identifier: " <>
              inspect(identifier)
    end
  end
end
