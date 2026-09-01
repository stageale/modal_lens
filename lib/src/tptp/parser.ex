defmodule Src.TPTP.Parser do
  @moduledoc """
  Parses the supported structural subset of TPTP documents.

  The parser recognizes THF annotated formulae and include directives
  while preserving the logical formulae themselves as raw TPTP syntax.
  """

  alias Src.TPTP.AnnotatedFormula
  alias Src.TPTP.Document
  alias Src.TPTP.Include

  @typedoc """
  Error encountered while structurally parsing a TPTP document.
  """
  @type parse_error ::
          {:file_error, String.t(), term()}
        | {:unsupported_construct, String.t()}
        | {:invalid_thf, String.t()}
        | {:invalid_include, String.t()}
        | {:invalid_role, String.t()}
        | {:unterminated_comment, :block}
        | {:unterminated_quote, :single | :double}
        | {:unbalanced_delimiter, String.t()}
        | {:unterminated_statement, String.t()}

  @typedoc """
  Option accepted by the TPTP parser.
  """
  @type option :: {:source, String.t()}

  @doc """
  Parses TPTP source text into a document.

  The optional `:source` value records the origin of the input without
  affecting parsing.
  """
  @spec parse(String.t(), [option()]) :: {:ok, Document.t()} | {:error, parse_error()}
  def parse(source, opts \\ []) when is_binary(source) do
    with {:ok, source} <- strip_comments(source),
        {:ok, statements} <- split_statements(source),
        {:ok, entries} <- parse_statements(statements) do
          {:ok, Document.new(entries, Keyword.get(opts, :source))}
        end
  end

  @doc """
  Reads and parses a TPTP file.

  Include directives are represented in the resulting document but are not recursively resolved.
  """
  @spec parse_file(String.t()) :: {:ok, Document.t()} | {:error, parse_error()}
  def parse_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, source} ->
        parse(source, source: path)

      {:error, reason} ->
        {:error, {:file_error, path, reason}}
    end
  end

  @spec strip_comments(String.t()) :: {:ok, String.t()} | {:error, parse_error()}
  defp strip_comments(source) do
    source
    |> String.to_charlist()
    |> do_strip_comments(:normal, false, [])
  end

  @spec do_strip_comments(charlist(), :normal | :line_comment | :block_comment | :single | :double, boolean(), charlist()) :: {:ok, String.t()} | {:error, parse_error()}
  defp do_strip_comments([], :normal, _escaped, acc), do: {:ok, acc |> Enum.reverse() |> List.to_string()}
  defp do_strip_comments([], :line_comment, _escaped, acc), do: {:ok, acc |> Enum.reverse() |> List.to_string()}
  defp do_strip_comments([], :block_comment, _escaped, _acc), do: {:error, {:unterminated_comment, :block}}
  defp do_strip_comments([], :single, _escaped, _acc), do: {:error, {:unterminated_quote, :single}}
  defp do_strip_comments([], :double, _escaped, _acc), do: {:error, {:unterminated_quote, :double}}
  defp do_strip_comments([?% | rest], :normal, _escaped, acc), do: do_strip_comments(rest, :line_comment, false, acc)
  defp do_strip_comments([?/, ?* | rest], :normal, _escaped, acc), do: do_strip_comments(rest, :block_comment, false, acc)
  defp do_strip_comments([?' | rest], :normal, _escaped, acc), do: do_strip_comments(rest, :single, false, [?' | acc])
  defp do_strip_comments([?" | rest], :normal, _escaped, acc), do: do_strip_comments(rest, :double, false, [?" | acc])
  defp do_strip_comments([char | rest], :normal, _escaped, acc), do: do_strip_comments(rest, :normal, false, [char | acc])
  defp do_strip_comments([?\n | rest], :line_comment, _escaped, acc), do: do_strip_comments(rest, :normal, false, acc)
  defp do_strip_comments([_char | rest], :line_comment, _escaped, acc), do: do_strip_comments(rest, :line_comment, false, acc)
  defp do_strip_comments([?*, ?/ | rest], :block_comment, _escaped, acc), do: do_strip_comments(rest, :normal, false, acc)
  defp do_strip_comments([_char | rest], :block_comment, _escaped, acc), do: do_strip_comments(rest, :block_comment, false, acc)

  defp do_strip_comments([char | rest], mode, true, acc)
       when mode in [:single, :double] do
    do_strip_comments(rest, mode, false, [char | acc])
  end
  defp do_strip_comments([?\\ | rest], mode, false, acc)
       when mode in [:single, :double] do
    do_strip_comments(rest, mode, true, [?\\ | acc])
  end

  defp do_strip_comments([?' | rest], :single, false, acc), do: do_strip_comments(rest, :normal, false, [?' | acc])
  defp do_strip_comments([?" | rest], :double, false, acc), do: do_strip_comments(rest, :normal, false, [?" | acc])

  defp do_strip_comments([char | rest], mode, false, acc)
       when mode in [:single, :double] do
    do_strip_comments(rest, mode, false, [char | acc])
  end

  @spec split_statements(String.t()) :: {:ok, [String.t()]} | {:error, parse_error()}
  defp split_statements(source) do
    with {:ok, parts} <- split_top_level(source, ?.) do
      {statements, [tail]} = Enum.split(parts, -1)

      if String.trim(tail) == "" do
        statements =
          statements
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, statements}
      else
        {:error, {:unterminated_statement, String.trim(tail)}}
      end
    end
  end

  @spec split_top_level(String.t(), char()) ::
          {:ok, [String.t()]} | {:error, parse_error()}
  defp split_top_level(source, delimiter) do
    initial = {0, 0, 0, nil, false, [], []}

    result =
      source
      |> String.to_charlist()
      |> Enum.reduce_while(initial, fn char,
                                        {round, square, curly, quote, escaped,
                                         current, parts} ->
        cond do
          quote != nil and escaped ->
            {:cont,
             {round, square, curly, quote, false, [char | current], parts}}

          quote != nil and char == ?\\ ->
            {:cont,
             {round, square, curly, quote, true, [char | current], parts}}

          quote == :single and char == ?' ->
            {:cont,
             {round, square, curly, nil, false, [char | current], parts}}

          quote == :double and char == ?" ->
            {:cont,
             {round, square, curly, nil, false, [char | current], parts}}

          quote != nil ->
            {:cont,
             {round, square, curly, quote, false, [char | current], parts}}

          char == ?' ->
            {:cont,
             {round, square, curly, :single, false, [char | current], parts}}

          char == ?" ->
            {:cont,
             {round, square, curly, :double, false, [char | current], parts}}

          char == ?( ->
            {:cont,
             {round + 1, square, curly, nil, false, [char | current], parts}}

          char == ?[ ->
            {:cont,
             {round, square + 1, curly, nil, false, [char | current], parts}}

          char == ?{ ->
            {:cont,
             {round, square, curly + 1, nil, false, [char | current], parts}}

          char == ?) and round > 0 ->
            {:cont,
             {round - 1, square, curly, nil, false, [char | current], parts}}

          char == ?] and square > 0 ->
            {:cont,
             {round, square - 1, curly, nil, false, [char | current], parts}}

          char == ?} and curly > 0 ->
            {:cont,
             {round, square, curly - 1, nil, false, [char | current], parts}}

          char == ?) ->
            {:halt, {:error, {:unbalanced_delimiter, ")"}}}

          char == ?] ->
            {:halt, {:error, {:unbalanced_delimiter, "]"}}}

          char == ?} ->
            {:halt, {:error, {:unbalanced_delimiter, "}"}}}

          char == delimiter and round == 0 and square == 0 and curly == 0 ->
            part =
              current
              |> Enum.reverse()
              |> List.to_string()

            {:cont, {0, 0, 0, nil, false, [], [part | parts]}}

          true ->
            {:cont,
             {round, square, curly, nil, false, [char | current], parts}}
        end
      end)
    case result do
      {:error, reason} ->
        {:error, reason}

      {_round, _square, _curly, :single, _escaped, _current, _parts} ->
        {:error, {:unterminated_quote, :single}}

      {_round, _square, _curly, :double, _escaped, _current, _parts} ->
        {:error, {:unterminated_quote, :double}}

      {round, square, curly, nil, _escaped, _current, _parts}
      when round != 0 or square != 0 or curly != 0 ->
        {:error, {:unbalanced_delimiter, "unexpected end of input"}}

      {0, 0, 0, nil, _escaped, current, parts} ->
        part = current |> Enum.reverse() |> List.to_string()
        {:ok, Enum.reverse([part | parts])}
    end
  end

  @spec parse_statements([String.t()]) :: {:ok, [Document.entry()]} | {:error, parse_error()}
  defp parse_statements(statements) do
    statements
    |> Enum.reduce_while({:ok, []}, fn statement, {:ok, entries} ->
      case parse_statement(statement) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end
  end

  @spec parse_statement(String.t()) :: {:ok, Document.entry()} | {:error, parse_error()}
  defp parse_statement(statement) do
    cond do
      Regex.match?(~r/^thf\s*\(/, statement) -> parse_thf(statement)
      Regex.match?(~r/^include\s*\(/, statement) -> parse_include(statement)
      true -> {:error, {:unsupported_construct, statement}}
    end
  end

  @spec parse_thf(String.t()) :: {:ok, AnnotatedFormula.t()} | {:error, parse_error()}
  defp parse_thf(statement)  do
    case Regex.run(~r/^thf\s*\((.*)\)$/s, statement, capture: :all_but_first) do
      [body] -> with {:ok, args} <- split_top_level(body, ?,) do
        build_thf(Enum.map(args, &String.trim/1))
      end

      _ -> {:error, {:invalid_thf, statement}}
    end
  end

  @spec build_thf([String.t()]) :: {:ok, AnnotatedFormula.t()} | {:error, parse_error()}
  defp build_thf([name, raw_role, formula]) do
    build_thf([name, raw_role, formula, nil, nil])
  end
  defp build_thf([name, raw_role, formula, source]) do
    build_thf([name, raw_role, formula, source, nil])
  end
  defp build_thf([name, raw_role, formula, source, useful_info]) when name != "" and formula != "" do
    with {:ok, role} <- parse_role(raw_role) do
      {:ok, AnnotatedFormula.new(name, role, formula, source, useful_info)}
    end
  end
  defp build_thf(args) do
    {:error, {:invalid_thf, inspect(args)}}
  end

  @spec parse_role(String.t()) :: {:ok, AnnotatedFormula.role()} | {:error, parse_error()}
  defp parse_role("axiom"), do: {:ok, :axiom}
  defp parse_role("hypothesis"), do: {:ok, :hypothesis}
  defp parse_role("definition"), do: {:ok, :definition}
  defp parse_role("assumption"), do: {:ok, :assumption}
  defp parse_role("lemma"), do: {:ok, :lemma}
  defp parse_role("theorem"), do: {:ok, :theorem}
  defp parse_role("corollary"), do: {:ok, :corollary}
  defp parse_role("conjecture"), do: {:ok, :conjecture}
  defp parse_role("negated_conjecture"), do: {:ok, :negated_conjecture}
  defp parse_role("plain"), do: {:ok, :plain}
  defp parse_role("type"), do: {:ok, :type}
  defp parse_role("interpretation"), do: {:ok, :interpretation}
  defp parse_role("logic"), do: {:ok, :logic}
  defp parse_role("unknown"), do: {:ok, :unknown}
  defp parse_role(role) do
    {:error, {:invalid_role, role}}
  end

  @spec parse_include(String.t()) :: {:ok, Include.t()} | {:error, parse_error()}
  defp parse_include(statement) do
    case Regex.run(~r/^include\s*\((.*)\)$/s, statement, capture: :all_but_first) do
      [body] ->
        with {:ok, args} <- split_top_level(body, ?,) do
          build_include(Enum.map(args, &String.trim/1))
        end
      _ -> {:error, {:invalid_include, statement}}
    end
  end

  @spec build_include([String.t()]) :: {:ok, Include.t()} | {:error, parse_error()}
  defp build_include([raw_file]) do
    with {:ok, file} <- parse_file_name(raw_file) do
      {:ok, Include.new(file)}
    end
  end
  defp build_include([raw_file, raw_selection]) do
    with {:ok, file} <- parse_file_name(raw_file),
        {:ok, selection} <- parse_selection(raw_selection) do
          {:ok, Include.new(file, selection)}
        end
  end
  defp build_include([raw_file, raw_selection, space]) do
    with {:ok, file} <- parse_file_name(raw_file),
        {:ok, selection} <- parse_selection(raw_selection) do
          {:ok, Include.new(file, selection, space)}
        end
  end
  defp build_include(args) do
    {:error, {:invalid_include, inspect(args)}}
  end

  @spec parse_file_name(String.t()) :: {:ok, String.t()} | {:error, parse_error()}
  defp parse_file_name(raw_file) do
    file = String.trim(raw_file)

    cond do
      file == "" -> {:error, {:invalid_include, "empty file name"}}

      String.starts_with?(file, "'") and String.ends_with?(file, "'") ->
        {:ok, String.slice(file, 1, String.length(file) - 2)}

      true -> {:ok, file}
    end
  end

  @spec parse_selection(String.t()) :: {:ok, Include.selection()} | {:error, parse_error()}
  defp parse_selection("*"), do: {:ok, :all}
  defp parse_selection(raw_selection) do
    case Regex.run(~r/^\[(.*)\]$/s, raw_selection, capture: :all_but_first) do
      [body] when body != "" ->
        with {:ok, names} <- split_top_level(body, ?,) do
          names =
            names
            |> Enum.map(&String.trim/1)

          if Enum.any?(names, &(&1 == "")) do
            {:error, {:invalid_include, raw_selection}}
          else
            {:ok, names}
          end
        end

      _ -> {:error, {:invalid_include, raw_selection}}
    end
  end
end
