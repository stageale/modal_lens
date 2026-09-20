defmodule Src.Core.BlockingAxiom do
  @moduledoc """
  Generates Isabelle/HOL blocking axioms for finite Nitpick models.

  A blocking axiom excludes finite structures matching a parsed Nitpick model
  over the represented signature. It is a technical search constraint used
  during countermodel enumeration and must not be interpreted as an additional
  object-level deontic or legal axiom.

  The generated structure description contains:

    * existentially quantified world representatives,
    * pairwise distinctness of those representatives,
    * a domain-closure condition,
    * the complete truth table of the parsed binary relation,
    * optionally the complete valuations of parsed unary predicates,
    * optionally the designated initial or actual world.

  Omitting proposition valuations or the designated world produces a blocking
  condition for the corresponding reduct of the model. Such a condition may
  therefore exclude more than one fully interpreted pointed model.

  Constants, functions, relations, and predicates that were not parsed into the
  model are not included in the blocking condition.
  """

  alias Src.Core.Model
  alias Src.Core.Model.DDL
  alias Src.Core.Model.EDSTIT
  alias Src.Core.Model.SDL

  @typedoc "A finite model supported by blocking-axiom generation."
  @type model :: SDL.t() | DDL.t() | EDSTIT.t()

  @typedoc "An Isabelle/HOL formula fragment."
  @type formula :: String.t()

  @typedoc "An Isabelle-compatible identifier."
  @type id :: String.t()

  @typedoc "A generated variable representing one model world."
  @type world_variable :: String.t()

  @typedoc "An option controlling the generated structure formula."
  @type structure_option ::
          {:include_atoms, boolean()}
          | {:include_designated_world, boolean()}
          | {:designated_world_constant, id()}
          | {:world_prefix, id()}

  @typedoc "Options controlling the generated structure formula."
  @type structure_options :: [structure_option()]

  @typedoc "An option controlling the generated blocking axiom."
  @type blocking_axiom_option ::
          structure_option()
          | {:name, String.t() | nil}

  @typedoc "Options controlling the generated blocking axiom."
  @type blocking_axiom_options :: [blocking_axiom_option()]

  @default_world_prefix "u"

  @isabelle_not ~S(\<not>)
  @isabelle_exists ~S(\<exists>)
  @isabelle_forall ~S(\<forall>)
  @isabelle_and ~S(\<and>)
  @isabelle_or ~S(\<or>)

  @doc """
  Sanitizes a generated Isabelle theorem name.
  """
  @spec sanitize_name(String.t()) :: id()
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

  @spec source_stem(model()) :: String.t()
  def source_stem(%{source: nil}) do
    "nitpick_model"
  end

  def source_stem(%{source: source})
      when is_binary(source) do
    source
    |> Path.basename()
    |> Path.rootname()
  end

  @doc """
  Produces an existential Isabelle/HOL formula describing `model`.

  The formula assigns a distinct bound variable to every model world, closes
  the world domain over those variables, and specifies every positive and
  negative edge of the parsed relation.

  Supported options are:

    * `:include_atoms` — includes the complete parsed proposition valuations.
      Defaults to `true`.

    * `:include_designated_world` — equates the appropriate Isabelle constant
      with the generated variable representing the model's designated world.
      Defaults to `false`.

    * `:designated_world_constant` — overrides the Isabelle constant used for
      the designated world. By default, the logic-specific value returned by
      `Src.Core.Model.designated_world_constant/1` is used.

    * `:world_prefix` — sets the prefix of generated world variables. Defaults
      to `"u"`.

  Raises `ArgumentError` when the model has an invalid cardinality, designated
  world, relation name, proposition name, or valuation.
  """
  @spec exact_structure_formula(model()) :: formula()
  @spec exact_structure_formula(model(), structure_options()) :: formula()
  def exact_structure_formula(%{} = model, opts \\ []) do
    validate_model!(model)

    include_atoms =
      Keyword.get(opts, :include_atoms, true)

    include_designated_world =
      Keyword.get(opts, :include_designated_world, false)

    designated_world_constant =
      Keyword.get(
        opts,
        :designated_world_constant,
        Model.designated_world_constant(model)
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

    agents =
      agent_variables(model)

    structural_clauses =
      [
        distinct_clause(worlds),
        domain_closure_clause(worlds)
      ] ++ agent_clauses(model, agents)

    initial_clauses =
      designated_world_clauses(
        model,
        worlds,
        include_designated_world,
        designated_world_constant
      )

    relation_clauses =
      relation_clauses(model, worlds, agents)

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
      Enum.join(worlds ++ agents, " ")

    """
    #{@isabelle_exists}#{quantified_worlds}.
      #{body}
    """
    |> String.trim()
  end

  @doc """
  Produces the negation of the exact structure formula for `model`.

  The returned formula can be embedded in a generated Isabelle axiom to
  exclude matching finite structures from subsequent Nitpick searches.
  """
  @spec blocking_formula(model()) :: formula()
  @spec blocking_formula(model(), structure_options()) :: formula()
  def blocking_formula(%{} = model, opts \\ []) do
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
  Wraps the blocking formula for `model` in a named Isabelle axiomatization.

  In addition to the structure options accepted by
  `exact_structure_formula/2`, the function accepts `:name`. The generated
  Isabelle theorem is named `ax_<sanitized-name>`.

  When `:name` is `nil` or absent, the name is derived from the model's source
  path.
  """
  @spec blocking_axiom(model()) :: String.t()
  @spec blocking_axiom(model(), blocking_axiom_options()) :: String.t()
  def blocking_axiom(model, opts \\ []) do
    requested_name = Keyword.get(opts, :name)
    axiom_name = sanitize_name(requested_name || source_stem(model))

    structure_opts = Keyword.delete(opts, :name)

    formula =
      model
      |> blocking_formula(structure_opts)
      |> indent_continuation(2)

    """
    axiomatization where
      ax_#{axiom_name}: "#{formula}"
    """
    |> String.trim()
  end

  @spec world_variables(pos_integer(), id()) :: [world_variable()]
  defp world_variables(cardinality, prefix) do
    for index <- 1..cardinality do
      "#{prefix}#{index}"
    end
  end

  @spec agent_variables(model()) :: [String.t()]
  defp agent_variables(%EDSTIT{agents: agents}) do
    agents
    |> Enum.with_index(1)
    |> Enum.map(fn {_agent, index} ->
      "a#{index}"
    end)
  end

  defp agent_variables(_model) do
    []
  end

  @spec distinct_clause([world_variable()]) :: formula()
  defp distinct_clause(worlds) do
    "distinct [#{Enum.join(worlds, ", ")}]"
  end

  @spec domain_closure_clause([world_variable()]) :: formula()
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

  @spec agent_clauses(model(), [String.t()]) :: [formula()]
  defp agent_clauses(%EDSTIT{}, agents) do
    distinct =
      case agents do
        [_first, _second | _rest] ->
          ["distinct [#{Enum.join(agents, ", ")}]"]

        _ ->
          []
      end

    active =
      Enum.map(agents, fn agent ->
        "(Agent #{agent})"
      end)

    distinct ++ active
  end

  defp agent_clauses(_model, _agents) do
    []
  end

  @spec relation_clauses(model(), [world_variable()], [String.t()]) :: [formula()]
  defp relation_clauses(%EDSTIT{} = model, worlds, agents) do
    ed_stit_relation_clauses(model, worlds, agents)
  end

  defp relation_clauses(%{} = model, worlds, _agents) do
    for source_index <-
          0..(model.cardinality - 1),
        target_index <-
          0..(model.cardinality - 1) do
      source_world =
        Enum.at(worlds, source_index)

      target_world =
        Enum.at(worlds, target_index)

      proposition =
        relation_proposition(model, source_world, target_world)

      truth =
        MapSet.member?(
          model.edges,
          {source_index, target_index}
        )

      literal(proposition, truth)
    end
  end

  defp ed_stit_relation_clauses(
         %EDSTIT{} = model,
         worlds,
         agent_variables
       ) do
    agent_map =
      model.agents
      |> Enum.zip(agent_variables)
      |> Map.new()

    model.modalities
    |> Enum.flat_map(fn modality ->
      modality_clauses(
        modality,
        model.cardinality,
        worlds,
        agent_map
      )
    end)
  end

  defp modality_clauses(
         %{kind: :settledness} = modality,
         cardinality,
         worlds,
         _agent_map
       ) do
    modality_accessibility_clauses(
      modality,
      cardinality,
      worlds,
      nil
    )
  end

  defp modality_clauses(
         %{agent: agent} = modality,
         cardinality,
         worlds,
         agent_map
       ) do
    agent_variable =
      Map.fetch!(
        agent_map,
        agent
      )

    modality_accessibility_clauses(
      modality,
      cardinality,
      worlds,
      agent_variable
    )
  end

  defp modality_accessibility_clauses(
         modality,
         cardinality,
         worlds,
         agent_variable
       ) do
    for source_index <-
          0..(cardinality - 1),
        target_index <-
          0..(cardinality - 1) do
      source_world =
        Enum.at(
          worlds,
          source_index
        )

      target_world =
        Enum.at(
          worlds,
          target_index
        )

      proposition =
        modality_proposition(
          modality,
          agent_variable,
          source_world,
          target_world
        )

      truth =
        MapSet.member?(
          modality.accessibility,
          {
            source_index,
            target_index
          }
        )

      literal(
        proposition,
        truth
      )
    end
  end

  defp modality_proposition(
         %{kind: :settledness, symbol: symbol},
         nil,
         source_world,
         target_world
       ) do
    "(#{symbol} #{source_world} #{target_world})"
  end

  defp modality_proposition(
         %{symbol: symbol},
         agent,
         source_world,
         target_world
       ) do
    "(#{symbol} #{agent} #{source_world} #{target_world})"
  end

  @spec relation_proposition(model(), world_variable(), world_variable()) :: formula()
  defp relation_proposition(%DDL{relation_name: relation_name}, source_world, target_world) do
    "((#{relation_name}) #{source_world} #{target_world})"
  end

  defp relation_proposition(%SDL{relation_name: relation_name}, source_world, target_world) do
    "(#{relation_name} #{source_world} #{target_world})"
  end

  @spec valuation_clauses(model(), [world_variable()], boolean()) :: [formula()]
  defp valuation_clauses(_model, _worlds, false) do
    []
  end

  defp valuation_clauses(%{} = model, worlds, true) do
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

  @spec designated_world_clauses(model(), [world_variable()], boolean(), id()) :: [formula()]
  defp designated_world_clauses(_model, _worlds, false, _constant) do
    []
  end

  defp designated_world_clauses(%{} = model, worlds, true, constant) do
    validate_isabelle_identifier!(constant, :designated_world_constant)

    designated_world =
      Enum.at(
        worlds,
        Model.designated_world(model)
      )

    ["(#{constant} = " <> "#{designated_world})"]
  end

  @spec literal(formula(), boolean()) :: formula()
  defp literal(proposition, true) do
    proposition
  end

  defp literal(proposition, false) do
    "#{@isabelle_not}#{proposition}"
  end

  @spec and_clauses([formula()], non_neg_integer()) :: formula()
  defp and_clauses(clauses, indentation) do
    separator =
      " #{@isabelle_and}\n" <>
        String.duplicate(
          " ",
          indentation
        )

    Enum.join(clauses, separator)
  end

  @spec indent(String.t(), non_neg_integer()) :: String.t()
  defp indent(text, spaces) do
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

  @spec indent_continuation(String.t(), non_neg_integer()) :: String.t()
  defp indent_continuation(text, spaces) do
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

  @spec sanitize_variable_prefix(String.t()) :: id()
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

  @spec validate_model!(model()) :: :ok
  defp validate_model!(%{cardinality: cardinality} = model)
       when cardinality > 0 do
    validate_designated_world!(model)
    validate_valuations!(model)
    validate_relation_name!(model)

    :ok
  end

  defp validate_model!(%{} = model) do
    raise ArgumentError,
          "blocking axioms require a positive finite cardinality, " <>
            "got: #{inspect(model.cardinality)}"
  end

  @spec validate_designated_world!(model()) :: :ok
  defp validate_designated_world!(model) do
    cardinality = model.cardinality
    designated_world = Model.designated_world(model)

    if designated_world < cardinality do
      :ok
    else
      raise ArgumentError,
            "designated world #{inspect(designated_world)} " <>
              "is outside cardinality #{inspect(cardinality)}"
    end
  end

  @spec validate_valuations!(model()) :: :ok
  defp validate_valuations!(%{} = model) do
    Enum.each(
      model.valuations,
      fn {predicate, values} ->
        validate_isabelle_identifier!(predicate, :predicate)

        unless length(values) == model.cardinality and
                 Enum.all?(values, &is_boolean/1) do
          raise ArgumentError,
                "valuation #{inspect(predicate)} must contain " <>
                  "exactly #{model.cardinality} Boolean values, " <>
                  "got: #{inspect(values)}"
        end
      end
    )
  end

  @spec validate_relation_name!(model()) :: :ok
  defp validate_relation_name!(%EDSTIT{} = model) do
    Enum.each(model.modalities, fn modality ->
      validate_isabelle_identifier!(modality.symbol, :modality)

      if modality.kind != :settledness and modality.agent not in model.agents do
        raise ArgumentError,
              "modality #{inspect(modality.symbol)}" <>
                "references unknown agent " <>
                inspect(modality.agent)
      end
    end)

    :ok
  end

  defp validate_relation_name!(%{relation_name: relation_name}) do
    validate_isabelle_identifier!(relation_name, :relation)
  end

  @spec validate_isabelle_identifier!(id(), atom()) :: :ok
  defp validate_isabelle_identifier!(identifier, kind)
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
