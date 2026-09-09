defmodule Src.Core.Parser do
  @moduledoc """
  Parsesf finite SDL and DDL models from Isabelle/Nitpick output.

  The parser extracts:

  * the Nitpick result kind and model cardinality,
  * the designated world,
  * the selected accessibility or preference relation,
  * unary proposition valuations,
  * and non-fatal parsing warnings.

  Parsed worlds are represented internally by zero-based integer indices.
  Nitpick world names such as `i1` and `i2` therefore become `0` and `1`.

  Depending on the `:model_logic` option, parsing returns either an
  `Src.Core.Model.SDL` or an `Src.Core.Model.DDL`
  """

  alias Src.Core.Model.DDL, as: DDLModel
  alias Src.Core.Model.SDL, as: SDLModel
  alias Src.Core.ParseWarning

  @typedoc "A model representation produced by the parser."
  @type model :: SDLModel.t() | DDLModel.t()

  @typedoc "A supported model logic."
  @type model_logic :: :sdl | :ddl

  @typedoc "The kind of finite structure reported by Nitpick."
  @type result_kind :: :model | :countermodel

  @typedoc "A zero-based world index."
  @type world_index :: non_neg_integer()

  @typedoc "A directed relation edge between two worlds."
  @type edge :: {world_index(), world_index()}

  @typedoc "A directed relation edge between two worlds."
  @type valuation :: [boolean()]

  @typedoc "A parser option accepted by `parse_nitpick_text/2`."
  @type parse_option ::
          {:model_logic, model_logic()}
          | {:relation, String.t()}
          | {:atoms, String.t() | [String.t()] | nil}
          | {:auto_atoms, boolean()}
          | {:source, String.t() | nil}

  @typedoc "Options controlling Nitpick parsing."
  @type parse_options :: [parse_option()]

  @type model_attributes :: %{
          required(:source) => String.t() | nil,
          required(:kind) => result_kind(),
          required(:cardinality) => non_neg_integer(),
          required(:relation_name) => String.t(),
          required(:edges) => MapSet.t(edge()),
          required(:valuations) => %{String.t() => valuation()},
          required(:warnings) => [ParseWarning.t()],
          required(:raw_text) => String.t()
        }

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

  @doc """
  Returns the regular expression used to parse Boolean relation assignments.

  The expression recognizes Nitpick entries such as:

      (i⇩1, i⇩2) := True
  """
  @spec world_pair_regex() :: Regex.t()
  def world_pair_regex, do: Regex.compile!(@world_pair)

  @doc """
  Returns the regular expression used to parse Boolean world assignments.

  The expression recognizes Nitpick entries such as:

      i⇩2 := False
  """
  @spec bool_assign_regex() :: Regex.t()
  def bool_assign_regex, do: Regex.compile!(@bool_assign)

  @doc """
  Reads and parses Nitpick output from `path`.

  The file path is stored as the source of the resulting model. All remaining
  options are forwarded to `parse_nitpick_text/2`.

  See `parse_nitpick_text/2` for the available parser options.

  Raises `File.Error` when the file cannot be read and `ArgumentError` when
  the text does not contain a parseable finite Nitpick model.
  """
  @spec parse_nitpick_file(Path.t()) :: model()
  @spec parse_nitpick_file(Path.t(), parse_options()) :: model()
  def parse_nitpick_file(path, opts \\ []) do
    text = File.read!(path)
    parse_nitpick_text(text, Keyword.put(opts, :source, path))
  end

  @doc """
  Parses the last Nitpick result contained in `text`.

  Supported options are:

  * `:model_logic` — model logic to construct; defaults to `:sdl`.
  * `:relation` — relation name to parse; defaults to `"R"`.
  * `:atoms` — requested atoms as a list or comma-separated string.
  * `:auto_atoms` — whether unary predicates should be detected automatically;
    defaults to `true`.
  * `:source` — optional source identifier stored in the model.

  If Nitpick does not report a designated world, world `i1` is selected and a
  warning is attached to the model. Missing relation edges and requested atoms
  also produce non-fatal warnings.

  Raises `ArgumentError` when no finite model or countermodel can be detected,
  when the model logic is unsupported, or when `:atoms` has an invalid form.
  """
  @spec parse_nitpick_text(String.t(), keyword()) :: model()
  def parse_nitpick_text(text, opts \\ []) do
    text = isolate_last_nitpick_result(text)

    model_logic = Keyword.get(opts, :model_logic, :sdl)
    relation = Keyword.get(opts, :relation, "R")

    atoms =
      opts
      |> Keyword.get(:atoms, [])
      |> normalize_atoms()

    auto_atoms = Keyword.get(opts, :auto_atoms, true)
    source = Keyword.get(opts, :source)

    {kind, cardinality} = parse_kind_and_cardinality(text)

    {designated_world, warnings} =
      case parse_designated_world(text) do
        nil ->
          {0, [%ParseWarning{message: "No explicit designated world found; defaulted to i1."}]}

        val ->
          {val, []}
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

  @spec build_model(atom(), model_attributes(), world_index()) :: model()
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

  @spec parse_kind_and_cardinality(String.t()) ::
          {result_kind(), non_neg_integer()}
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

  @spec parse_designated_world(String.t()) :: world_index() | nil
  defp parse_designated_world(text) do
    pattern = Regex.compile!("(?:^|\\n)\\s*(?:w|aw|actual_world|initial_world)\\s*=\\s*#{@world}")

    case Regex.run(pattern, text) do
      nil -> nil
      [_, world_num_str] -> String.to_integer(world_num_str) - 1
    end
  end

  @spec parse_relation_edges(
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: MapSet.t(edge())
  defp parse_relation_edges(text, relation, cardinality) do
    parse_flat_relation_edges(text, relation, cardinality)
    |> MapSet.union(parse_nested_relation_edges(text, relation, cardinality))
  end

  @spec parse_flat_relation_edges(
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: MapSet.t(edge())
  defp parse_flat_relation_edges(text, relation, cardinality) do
    case extract_assignment_block(text, relation, true) do
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

  @spec parse_nested_relation_edges(
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: MapSet.t(edge())
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

  @spec parse_unary_predicate(
          String.t(),
          String.t(),
          non_neg_integer()
        ) :: valuation() | nil
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

  @spec detect_unary_predicates(
          String.t(),
          non_neg_integer(),
          MapSet.t(String.t())
        ) :: %{String.t() => valuation()}
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

  @spec extract_assignment_block(
          String.t(),
          String.t(),
          boolean()
        ) :: String.t() | nil
  defp extract_assignment_block(text, name, allow_parenthesized) do
    escaped = Regex.escape(name)

    lhs =
      if allow_parenthesized do
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

  @spec normalize_atoms(nil | String.t() | [String.t()]) ::
          [String.t()]
  defp normalize_atoms(nil), do: []
  defp normalize_atoms(""), do: []
  defp normalize_atoms("-"), do: []

  defp normalize_atoms(atoms) when is_binary(atoms) do
    atoms
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms) when is_list(atoms) do
    atoms
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_atoms(atoms) do
    raise ArgumentError,
          "atoms must be a comma-separated string or a list of strings, got: " <>
            inspect(atoms)
  end

  @spec isolate_last_nitpick_result(String.t()) :: String.t()
  defp isolate_last_nitpick_result(text) do
    case Regex.scan(@nitpick_result_header, text, return: :index) do
      [] ->
        text

      matches ->
        [{start_position, _length}] = List.last(matches)

        binary_part(text, start_position, byte_size(text) - start_position)
    end
  end
end
