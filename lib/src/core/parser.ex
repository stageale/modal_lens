defmodule Src.Core.Parser do
  alias Src.Core.Model.DDL, as: DDLModel
  alias Src.Core.Model.SDL, as: SDLModel
  alias Src.Err.ParseWarning

  @world ~S/i(?:⇩|\\<\^sub>)(\d+)/
  @world_pair "\\(#{@world}\\s*,\\s*#{@world}\\)\\s*:?=\\s*(True|False)"
  @bool_assign "#{@world}\\s*:=\\s*(True|False)"
  @identifier ~S/[A-Za-z][A-Za-z0-9_'.?]*/
  @nitpick_result_header ~r/
    Nitpick\ found\
    (?:
      a\ counterexample\ for\ card\ i\s*=\s*\d+\s*: |
      a\ model\ for\ card\ i\s*=\s*\d+\s*: |
      no counterexample[^\n]* |
      no model[^\n]*
    )
  /x

  def world_pair_regex, do: Regex.compile!(@world_pair)
  def bool_assign_regex, do: Regex.compile!(@bool_assign)
  # *
  def parse_nitpick_file(path, opts \\ []) do
    text = File.read!(path)
    parse_nitpick_text(text, Keyword.put(opts, :source, path))
  end

  # *
  def parse_nitpick_text(text, opts) do
    text = isolate_last_nitpick_result(text)

    model_logic = Keyword.get(opts, :model_logic, :sdl)
    relation = Keyword.get(opts, :relation, "R")
    atoms = Keyword.get(opts, :atoms, [])
    auto_atoms = Keyword.get(opts, :auto_atoms, false)
    source = Keyword.get(opts, :source)

    {kind, cardinality} = parse_kind_and_cardinality(text)

    {designated_world, warnings} =
      case parse_designated_world(text) do
        nil -> {0, [%ParseWarning{message: "No explicit designated world found; defaulted to i1."}]}
        val -> {val, []}
      end

    edge_set = parse_relation_edges(text, relation, cardinality)

    warnings =
      if MapSet.size(edge_set) == 0 do
        [%ParseWarning{message: "No true edges found for relation '#{relation}'."} | warnings]
      else
        warnings
      end

    requested_atoms =
      if auto_atoms do
        detected = detect_unary_predicates(text, cardinality, MapSet.new([relation]))
        Enum.uniq(atoms ++ Map.keys(detected))
      else
        atoms
      end

    {valuations, final_warnings} =
      Enum.reduce(requested_atoms, {%{}, warnings}, fn atom, {acc_vals, acc_warns} ->
        case parse_unary_predicate(text, atom, cardinality) do
          nil ->
            {acc_vals, [%ParseWarning{message: "Atom '#{atom}' not found; omitted."} | acc_warns]}

          vals ->
            {Map.put(acc_vals, atom, vals), acc_warns}
        end
      end)

    attributes = %{
      source: source,
      kind: kind,
      cardinality: cardinality,
      relation_name: relation,
      edges: edge_set,
      valuations: valuations,
      warnings: Enum.reverse(final_warnings),
      raw_text: text
    }

    build_model(
      model_logic,
      attributes,
      designated_world
    )
  end

  defp build_model(:sdl, attributes, designated_world) do
    struct!(
      SDLModel,
      Map.put(
        attributes,
        :initial_world,
        designated_world
      )
    )
  end

  defp build_model(:ddl, attributes, designated_world) do
    struct!(
      DDLModel,
      Map.put(
        attributes,
        :actual_world,
        designated_world
      )
    )
  end

  defp build_model(model_logic, _attributes, _world) do
    raise ArgumentError,
          "unsupported model logic: #{inspect(model_logic)}"
  end

  # *
  defp parse_kind_and_cardinality(text) do
    cond do
      m = Regex.run(~r/Nitpick found a counterexample for card i\s*=\s*(\d+)/, text) ->
        [_, card_str] = m
        {:countermodel, String.to_integer(card_str)}

      m = Regex.run(~r/Nitpick found a model for card i\s*=\s*(\d+)/, text) ->
        [_, card_str] = m
        {:model, String.to_integer(card_str)}

      String.contains?(text, "Nitpick found no counterexample") ->
        raise ArgumentError,
              "Nitpick found no counterexample; no finite model/countermodel to parse."

      true ->
        raise ArgumentError,
              "Could not detect 'Nitpick found a model/countermodel for card i = n'."
    end
  end

  # *
  defp parse_designated_world(text) do
    pattern = Regex.compile!("(?:^|\\n)\\s*(?:w|aw|actual_world|initial_world)\\s*=\\s*#{@world}")

    case Regex.run(pattern, text) do
      nil -> nil
      [_, world_num_str] -> String.to_integer(world_num_str) - 1
    end
  end

  # *
  defp parse_relation_edges(text, relation, cardinality) do
    parse_flat_relation_edges(text, relation, cardinality)
    |> MapSet.union(parse_nested_relation_edges(text, relation, cardinality))
  end

  # *
  defp parse_flat_relation_edges(text, relation, cardinality) do
    case extract_assignment_block(text, relation, true) do
      # * Prevent FunctionClauseError
      nil ->
        MapSet.new()

      assignment ->
        for [_, a, b, "True"] <- Regex.scan(world_pair_regex(), assignment),
            ai = String.to_integer(a) - 1,
            bi = String.to_integer(b) - 1,
            ai in 0..(cardinality - 1),
            bi in 0..(cardinality - 1),
            into: MapSet.new(),
            do: {ai, bi}
    end
  end

  # *
  defp parse_nested_relation_edges(text, relation, cardinality) do
    case extract_assignment_block(text, relation, true) do
      nil ->
        MapSet.new()

      assignment ->
        block_pattern = Regex.compile!("#{@world}\\s*:=\\s*\\(λx\\.\\s*_\\)\\s*\\(([^)]*)\\)")

        for [_, src_str, inner] <- Regex.scan(block_pattern, assignment),
            src_idx = String.to_integer(src_str) - 1,
            src_idx in 0..(cardinality - 1),
            [_, tgt_str, "True"] <- Regex.scan(bool_assign_regex(), inner),
            tgt_idx = String.to_integer(tgt_str) - 1,
            tgt_idx in 0..(cardinality - 1),
            into: MapSet.new() do
          {src_idx, tgt_idx}
        end
    end
  end

  # *
  defp parse_unary_predicate(text, atom, cardinality) do
    case extract_assignment_block(text, atom, true) do
      nil ->
        nil

      assignment ->
        found =
          for [_, w, val] <- Regex.scan(bool_assign_regex(), assignment),
              idx = String.to_integer(w) - 1,
              into: %{},
              do: {idx, val == "True"}

        if map_size(found) == 0 do
          nil
        else
          for i <- 0..(cardinality - 1) do
            Map.get(found, i, false)
          end
        end
    end
  end

  # *
  defp detect_unary_predicates(text, cardinality, exclude) do
    pattern = Regex.compile!("(?:^|\\n)\\s*(#{@identifier})\\s*=\\s*\\(λx\\.\\s*_\\)")

    for [_, name] <- Regex.scan(pattern, text),
        not MapSet.member?(exclude, name),
        not String.starts_with?(name, "??"),
        val = parse_unary_predicate(text, name, cardinality),
        val != nil,
        into: %{},
        do: {name, val}
  end

  # *
  defp extract_assignment_block(text, name, allow_paranthesized) do
    escaped = Regex.escape(name)

    lhs =
      if allow_paranthesized do
        "(?:\\(#{escaped}\\)|#{escaped})"
      else
        escaped
      end

    start_pattern = Regex.compile!("(?:^|\\n)\\s*#{lhs}\\s*=")

    case Regex.run(start_pattern, text, return: :index) do
      nil ->
        nil

      [{start_pos, length}] ->
        rest = binary_part(text, start_pos, byte_size(text) - start_pos)
        search_offset = length
        text_after_match = binary_part(rest, search_offset, byte_size(rest) - search_offset)

        next_assign_pattern =
          Regex.compile!(
            "\\n\\s*(?:#{@identifier}|\\(#{@identifier}\\)|λx\\.\\s*\\?\\?\\.[^=]+)\\s*="
          )

        case Regex.run(next_assign_pattern, text_after_match, return: :index) do
          nil ->
            rest

          [{next_start, _}] ->
            block_end = search_offset + next_start
            binary_part(rest, 0, block_end)
        end
    end
  end

  defp isolate_last_nitpick_result(text) do
    case Regex.scan(@nitpick_result_header, text, return: :index) do
      [] -> text
      matches ->
        [{start_position, _length}] = List.last(matches)

        binary_part(text, start_position, byte_size(text) - start_position)
    end
  end
end
