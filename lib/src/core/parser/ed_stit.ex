defmodule Src.Core.Parser.EDSTIT do
  @moduledoc """
  Parser for finite Epistemic Deontic STIT models produced by Nitpick.

  The parser is deliberately isolated from the existing SDL/DDL parser.
  It extracts:

    * the finite world domain,
    * the actual world,
    * active agents,
    * the settledness modality `RBox`,
    * agent-indexed STIT modalities `RStit`,
    * agent-indexed deontic modalities `ROught`,
    * agent-indexed belief modalities `RBel`,
    * and propositional valuations.

  World and agent indices are represented internally as zero-based integers.
  """

  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Core.Model.Modality
  alias Src.Core.ParseWarning

  @world ~S/i(?:⇩|\\<\^sub>)(\d+)/
  @agent ~S/ag(?:⇩|\\<\^sub>)(\d+)/

  @identifier ~S/[A-Za-z][A-Za-z0-9_'.?]*/

  @world_pair "\\(#{@world}\\s*,\\s*#{@world}\\)\\s*:?=\\s*(True|False)"

  @bool_assign "#{@world}\\s*:=\\s*(True|False)"

  @agent_bool_assign "#{@agent}\\s*:=\\s*(True|False)"

  @flat_agent_relation (
    "\\(#{@agent}\\s*,\\s*#{@world}\\s*,\\s*#{@world}\\)" <>
      "\\s*:?=\\s*(True|False)"
  )

  @nested_agent_relation (
    "\\(\\s*\\(#{@agent}\\s*,\\s*#{@world}\\)\\s*," <>
      "\\s*#{@world}\\s*\\)" <>
      "\\s*:?=\\s*(True|False)"
  )

  @agent_predicate "Agent"

  @modalities %{
    settledness: "RBox",
    stit: "RStit",
    ought: "ROught",
    belief: "RBel"
  }

  @nitpick_result_header ~r/
    Nitpick\ found\
    (?:
      a\ counterexample\ for\ card\ i\s*=\s*\d+\s*: |
      a\ model\ for\ card\ i\s*=\s*\d+\s*: |
      no\ counterexample[^\n]* |
      no\ model[^\n]*
    )
  /x

  @doc """
  Parses an Epistemic Deontic STIT model from Nitpick output.
  """
  @spec parse(String.t(), keyword()) :: EDSTITModel.t()
  def parse(text, opts \\ []) do
    text =
      isolate_last_nitpick_result(text)

    source =
      Keyword.get(opts, :source)

    atoms =
      opts
      |> Keyword.get(:atoms, [])
      |> normalize_atoms()

    auto_atoms =
      Keyword.get(opts, :auto_atoms, true)

    {kind, cardinality} =
      parse_kind_and_cardinality(text)

    {actual_world, warnings} =
      parse_actual_world(text)

    agent_names =
      parse_agent_constant_names(text)

    active_agents =
      parse_active_agent_indices(text)

    inferred_agents =
      infer_agent_indices(text)

    agent_indices =
      if MapSet.size(active_agents) > 0 do
        active_agents
      else
        inferred_agents
        |> MapSet.union(
          agent_names
          |> Map.keys()
          |> MapSet.new()
        )
      end

    agent_entries =
      agent_indices
      |> Enum.sort()
      |> Enum.map(fn index ->
        {
          index,
          Map.get(
            agent_names,
            index,
            "ag#{index + 1}"
          )
        }
      end)

    modalities =
      parse_modalities(
        text,
        cardinality,
        agent_entries
      )

    agents =
      Enum.map(
        agent_entries,
        fn {_index, name} ->
          name
        end
      )

    excluded =
      @modalities
      |> Map.values()
      |> MapSet.new()
      |> MapSet.put(@agent_predicate)

    requested_atoms =
      if auto_atoms do
        detected =
          detect_unary_predicates(
            text,
            cardinality,
            excluded
          )

        Enum.uniq(atoms ++ Map.keys(detected))
      else
        atoms
      end

    {valuations, warnings} =
      parse_valuations(
        text,
        requested_atoms,
        cardinality,
        warnings
      )

    %EDSTITModel{
      source: source,
      kind: kind,
      cardinality: cardinality,
      actual_world: actual_world,
      agents: agents,
      modalities: modalities,
      valuations: valuations,
      warnings: Enum.reverse(warnings),
      raw_text: text
    }
  end

  # ---------------------------------------------------------------------------
  # Modalities
  # ---------------------------------------------------------------------------

  defp parse_modalities(text, cardinality, agent_entries) do
    settledness =
      Modality.new!(
        @modalities.settledness,
        :settledness,
        parse_binary_relation(
          text,
          @modalities.settledness,
          cardinality
        )
      )

    indexed =
      Enum.flat_map(
        agent_entries,
        fn {agent_index, agent_name} ->
          [
            parse_agent_modality(
              text,
              cardinality,
              agent_index,
              agent_name,
              :stit
            ),
            parse_agent_modality(
              text,
              cardinality,
              agent_index,
              agent_name,
              :ought
            ),
            parse_agent_modality(
              text,
              cardinality,
              agent_index,
              agent_name,
              :belief
            )
          ]
        end
      )

    [settledness | indexed]
  end

  defp parse_agent_modality(text, cardinality, agent_index, agent_name, kind) do
    symbol =
      Map.fetch!(
        @modalities,
        kind
      )

    accessibility =
      parse_agent_indexed_relation(
        text,
        symbol,
        agent_index,
        cardinality
      )

    Modality.new!(
      symbol,
      kind,
      accessibility,
      agent: agent_name
    )
  end

  # ---------------------------------------------------------------------------
  # Binary settledness relation
  # ---------------------------------------------------------------------------

  defp parse_binary_relation(text, symbol, cardinality) do
    case extract_assignment_block(
           text,
           symbol
         ) do
      nil ->
        MapSet.new()

      assignment ->
        parse_binary_edges(
          assignment,
          cardinality
        )
    end
  end

  defp parse_binary_edges(
         assignment,
         cardinality
       ) do
    flat =
      parse_flat_binary_edges(
        assignment,
        cardinality
      )

    nested =
      parse_nested_binary_edges(
        assignment,
        cardinality
      )

    MapSet.union(
      flat,
      nested
    )
  end

  defp parse_flat_binary_edges(
         assignment,
         cardinality
       ) do
    pattern =
      Regex.compile!(@world_pair)

    for [_, source, target, "True"] <-
          Regex.scan(
            pattern,
            assignment
          ),
        source_index =
          String.to_integer(source) - 1,
        target_index =
          String.to_integer(target) - 1,
        valid_world?(
          source_index,
          cardinality
        ),
        valid_world?(
          target_index,
          cardinality
        ),
        into: MapSet.new() do
      {
        source_index,
        target_index
      }
    end
  end

  defp parse_nested_binary_edges(
         assignment,
         cardinality
       ) do
    block_pattern =
      Regex.compile!(
        "#{@world}\\s*:=\\s*" <>
          "\\(λx\\.\\s*_\\)\\s*" <>
          "\\(([^)]*)\\)"
      )

    bool_pattern =
      Regex.compile!(@bool_assign)

    for [_, source, inner] <-
          Regex.scan(
            block_pattern,
            assignment
          ),
        source_index =
          String.to_integer(source) - 1,
        valid_world?(
          source_index,
          cardinality
        ),
        [_, target, "True"] <-
          Regex.scan(
            bool_pattern,
            inner
          ),
        target_index =
          String.to_integer(target) - 1,
        valid_world?(
          target_index,
          cardinality
        ),
        into: MapSet.new() do
      {
        source_index,
        target_index
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Agent-indexed modalities
  # ---------------------------------------------------------------------------

  defp parse_agent_indexed_relation(
         text,
         symbol,
         agent_index,
         cardinality
       ) do
    case extract_assignment_block(
           text,
           symbol
         ) do
      nil ->
        MapSet.new()

      assignment ->
        flat =
          parse_flat_agent_edges(
            assignment,
            agent_index,
            cardinality
          )

        nested =
          parse_nested_agent_edges(
            assignment,
            agent_index,
            cardinality
          )

        curried =
          parse_curried_agent_edges(
            assignment,
            agent_index,
            cardinality
          )

        [flat, nested, curried]
        |> Enum.concat()
        |> MapSet.new()
    end
  end

  defp parse_flat_agent_edges(
         assignment,
         wanted_agent,
         cardinality
       ) do
    pattern =
      Regex.compile!(@flat_agent_relation)

    for [_, agent, source, target, "True"] <-
          Regex.scan(
            pattern,
            assignment
          ),
        agent_index =
          String.to_integer(agent) - 1,
        agent_index == wanted_agent,
        source_index =
          String.to_integer(source) - 1,
        target_index =
          String.to_integer(target) - 1,
        valid_world?(
          source_index,
          cardinality
        ),
        valid_world?(
          target_index,
          cardinality
        ),
        into: MapSet.new() do
      {
        source_index,
        target_index
      }
    end
  end

  defp parse_nested_agent_edges(
         assignment,
         wanted_agent,
         cardinality
       ) do
    pattern =
      Regex.compile!(@nested_agent_relation)

    for [_, agent, source, target, "True"] <-
          Regex.scan(
            pattern,
            assignment
          ),
        agent_index =
          String.to_integer(agent) - 1,
        agent_index == wanted_agent,
        source_index =
          String.to_integer(source) - 1,
        target_index =
          String.to_integer(target) - 1,
        valid_world?(
          source_index,
          cardinality
        ),
        valid_world?(
          target_index,
          cardinality
        ),
        into: MapSet.new() do
      {
        source_index,
        target_index
      }
    end
  end

  defp parse_curried_agent_edges(
         assignment,
         agent_index,
         cardinality
       ) do
    case extract_agent_slice(
           assignment,
           agent_index
         ) do
      nil ->
        MapSet.new()

      slice ->
        parse_binary_edges(
          slice,
          cardinality
        )
    end
  end

  defp extract_agent_slice(
         assignment,
         wanted_agent
       ) do
    pattern =
      Regex.compile!("#{@agent}\\s*:?=\\s*")

    entries =
      pattern
      |> Regex.scan(
        assignment,
        return: :index
      )
      |> Enum.map(fn
        [
          {start, _length},
          {agent_start, agent_length}
        ] ->
          agent =
            assignment
            |> binary_part(
              agent_start,
              agent_length
            )
            |> String.to_integer()
            |> Kernel.-(1)

          {
            agent,
            start
          }
      end)

    case Enum.find_index(
           entries,
           fn {agent, _start} ->
             agent == wanted_agent
           end
         ) do
      nil ->
        nil

      position ->
        {_agent, start} =
          Enum.at(
            entries,
            position
          )

        stop =
          case Enum.at(
                 entries,
                 position + 1
               ) do
            nil ->
              byte_size(assignment)

            {_agent, next_start} ->
              next_start
          end

        binary_part(
          assignment,
          start,
          stop - start
        )
    end
  end

  # ---------------------------------------------------------------------------
  # Agents
  # ---------------------------------------------------------------------------

  defp parse_active_agent_indices(text) do
    case extract_assignment_block(
           text,
           @agent_predicate
         ) do
      nil ->
        MapSet.new()

      assignment ->
        pattern =
          Regex.compile!(@agent_bool_assign)

        for [_, agent, "True"] <-
              Regex.scan(
                pattern,
                assignment
              ),
            into: MapSet.new() do
          String.to_integer(agent) - 1
        end
    end
  end

  defp parse_agent_constant_names(text) do
    pattern =
      Regex.compile!(
        "(?:^|\\n)\\s*" <>
          "(#{@identifier})\\s*=\\s*" <>
          "#{@agent}"
      )

    for [_, name, agent] <-
          Regex.scan(
            pattern,
            text
          ),
        into: %{} do
      {
        String.to_integer(agent) - 1,
        name
      }
    end
  end

  defp infer_agent_indices(text) do
    [:stit, :ought, :belief]
    |> Enum.reduce(
      MapSet.new(),
      fn kind, acc ->
        symbol =
          Map.fetch!(
            @modalities,
            kind
          )

        case extract_assignment_block(
               text,
               symbol
             ) do
          nil ->
            acc

          assignment ->
            found =
              Regex.compile!(@agent)
              |> Regex.scan(assignment)
              |> Enum.map(fn [_, agent] ->
                String.to_integer(agent) - 1
              end)
              |> MapSet.new()

            MapSet.union(
              acc,
              found
            )
        end
      end
    )
  end

  # ---------------------------------------------------------------------------
  # Valuations
  # ---------------------------------------------------------------------------

  defp parse_valuations(
         text,
         atoms,
         cardinality,
         warnings
       ) do
    Enum.reduce(
      atoms,
      {%{}, warnings},
      fn atom, {valuations, warnings} ->
        case parse_unary_predicate(
               text,
               atom,
               cardinality
             ) do
          nil ->
            {
              valuations,
              [
                %ParseWarning{
                  message: "Atom '#{atom}' not found; omitted."
                }
                | warnings
              ]
            }

          values ->
            {
              Map.put(
                valuations,
                atom,
                values
              ),
              warnings
            }
        end
      end
    )
  end

  defp parse_unary_predicate(
         text,
         atom,
         cardinality
       ) do
    case extract_assignment_block(
           text,
           atom
         ) do
      nil ->
        nil

      assignment ->
        pattern =
          Regex.compile!(@bool_assign)

        found =
          for [_, world, value] <-
                Regex.scan(
                  pattern,
                  assignment
                ),
              index =
                String.to_integer(world) - 1,
              into: %{} do
            {
              index,
              value == "True"
            }
          end

        if map_size(found) == 0 do
          nil
        else
          for index <-
                0..(cardinality - 1) do
            Map.get(
              found,
              index,
              false
            )
          end
        end
    end
  end

  defp detect_unary_predicates(
         text,
         cardinality,
         excluded
       ) do
    pattern =
      Regex.compile!(
        "(?:^|\\n)\\s*" <>
          "(#{@identifier})\\s*=\\s*" <>
          "\\(λx\\.\\s*_\\)"
      )

    for [_, name] <-
          Regex.scan(
            pattern,
            text
          ),
        not MapSet.member?(
          excluded,
          name
        ),
        not String.starts_with?(
          name,
          "??"
        ),
        valuation =
          parse_unary_predicate(
            text,
            name,
            cardinality
          ),
        valuation != nil,
        into: %{} do
      {
        name,
        valuation
      }
    end
  end

  # ---------------------------------------------------------------------------
  # Nitpick metadata
  # ---------------------------------------------------------------------------

  defp parse_kind_and_cardinality(text) do
    cond do
      match =
          Regex.run(
            ~r/Nitpick found a counterexample for card i\s*=\s*(\d+)/,
            text
          ) ->
        [_, cardinality] =
          match

        {
          :countermodel,
          String.to_integer(cardinality)
        }

      match =
          Regex.run(
            ~r/Nitpick found a model for card i\s*=\s*(\d+)/,
            text
          ) ->
        [_, cardinality] =
          match

        {
          :model,
          String.to_integer(cardinality)
        }

      String.contains?(
        text,
        "Nitpick found no counterexample"
      ) ->
        raise ArgumentError,
              "Nitpick found no counterexample; no finite model/countermodel to parse."

      true ->
        raise ArgumentError,
              "Could not detect 'Nitpick found a model/countermodel for card i = n'."
    end
  end

  defp parse_actual_world(text) do
    pattern =
      Regex.compile!(
        "(?:^|\\n)\\s*" <>
          "(?:actual_world|aw|w)" <>
          "\\s*=\\s*#{@world}"
      )

    case Regex.run(
           pattern,
           text
         ) do
      [_, world] ->
        {
          String.to_integer(world) - 1,
          []
        }

      nil ->
        {
          0,
          [
            %ParseWarning{
              message: "No explicit actual world found; defaulted to i1."
            }
          ]
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Assignment blocks
  # ---------------------------------------------------------------------------

  defp extract_assignment_block(
         text,
         name
       ) do
    escaped =
      Regex.escape(name)

    start_pattern =
      Regex.compile!(
        "(?:^|\\n)\\s*" <>
          "(?:\\(#{escaped}\\)|#{escaped})" <>
          "\\s*="
      )

    case Regex.run(
           start_pattern,
           text,
           return: :index
         ) do
      nil ->
        nil

      [{start_position, match_length}] ->
        rest =
          binary_part(
            text,
            start_position,
            byte_size(text) - start_position
          )

        after_match =
          binary_part(
            rest,
            match_length,
            byte_size(rest) - match_length
          )

        next_assignment =
          Regex.compile!(
            "\\n\\s*" <>
              "(?:#{@identifier}|\\(#{@identifier}\\))" <>
              "\\s*="
          )

        case Regex.run(
               next_assignment,
               after_match,
               return: :index
             ) do
          nil ->
            rest

          [{next_start, _length}] ->
            binary_part(
              rest,
              0,
              match_length + next_start
            )
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Options and result selection
  # ---------------------------------------------------------------------------

  defp normalize_atoms(nil),
    do: []

  defp normalize_atoms(""),
    do: []

  defp normalize_atoms("-"),
    do: []

  defp normalize_atoms(atoms)
       when is_binary(atoms) do
    atoms
    |> String.split(
      ",",
      trim: true
    )
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms)
       when is_list(atoms) do
    atoms
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms) do
    raise ArgumentError,
          "atoms must be a comma-separated string or a list of strings, got: " <>
            inspect(atoms)
  end

  defp isolate_last_nitpick_result(text) do
    case Regex.scan(
           @nitpick_result_header,
           text,
           return: :index
         ) do
      [] ->
        text

      matches ->
        [{start_position, _length}] =
          List.last(matches)

        binary_part(
          text,
          start_position,
          byte_size(text) - start_position
        )
    end
  end

  defp valid_world?(world, cardinality) do
    world >= 0 and
      world < cardinality
  end
end
