defmodule Src.ModelEnumeration.SearchTheory do
  @moduledoc """
  Generates Isabelle search theories for model enumeration.

  A search theory imports the unchanged based theory, inserts all blocking
  axioms found so far, and selects the Nitpick template for the enumeration mode.
  """

  @template_dir Path.expand("../../data/mod", __DIR__)

  @blocking_marker "(* AXIOM_REFINER_BLOCKS *)"
  @search_theory_placeholder "AXIOM_REFINER_SEARCH"
  @input_theory_placeholder "AXIOM_REFINER_INPUT"

  @type t :: %{
    mode: atom(),
    theory_name: String.t(),
    theory_path: String.t(),
    template_path: String.t(),
    base_theory_path: String.t(),
    base_theory_name: String.t(),
    block_count: non_neg_integer(),
    blocking_axioms: [String.t()]
  }

  @doc """
  Writes a search theory for the given base theory and blocking axioms.
  """
  @spec write(String.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def write(base_theory_path, blocking_axioms, opts) when is_binary(base_theory_path) and is_list(blocking_axioms) and is_list(opts) do
    base_theory_path = Path.expand(base_theory_path)
    mode = Keyword.fetch!(opts, :mode)

    base_theory_name =
      Path.basename(base_theory_path, ".thy")

    block_count = length(blocking_axioms)

    theory_name = search_theory_name(base_theory_name, block_count)

    theory_dir =
      opts
      |> Keyword.get(:search_theory_dir, Path.dirname(base_theory_path))
      |> Path.expand()

    theory_path = Path.join(theory_dir, "#{theory_name}.thy")

    template_path = template_path(mode)

    with :ok <- validate_blocking_axioms(blocking_axioms),
        {:ok, template} <- read_template(template_path),
         :ok <- ensure_blocking_marker(template, template_path),
         :ok <- create_directory(theory_dir),
         source = generate_source(template, theory_name, base_theory_path, theory_dir, blocking_axioms),
         :ok <- write_theory(theory_path, source) do
          {:ok,
            %{
              mode: mode,
              theory_name: theory_name,
              theory_path: theory_path,
              template_path: template_path,
              base_theory_path: base_theory_path,
              base_theory_name: base_theory_name,
              block_count: block_count,
              blocking_axioms: blocking_axioms
            }
          }
         end
  end

  defp generate_source(template, theory_name, base_theory_path, theory_dir, blocking_axioms) do
    base_theory_import =
      base_theory_path
      |> Path.rootname()
      |> Path.relative_to(theory_dir)
      |> String.replace("\\", "/")
      |> then(&~s("#{&1}"))

    template
    |> String.replace(@search_theory_placeholder, theory_name, global: false)
    |> String.replace(@input_theory_placeholder, base_theory_import, global: false)
    |> insert_blocking_axioms(blocking_axioms)
  end

  defp insert_blocking_axioms(source, blocking_axioms) do
    rendered_blocks =
      blocking_axioms
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {axiom, index} ->
        """
        (* Automatically generated blocking axiom #{index}. *)
        #{axiom}
        """
        |> String.trim()
      end)

    replacement =
      """
      #{rendered_blocks}

      #{@blocking_marker}
      """
      |> String.trim()

    String.replace(source, @blocking_marker, replacement, global: false)
  end

  defp search_theory_name(base_theory_name, block_count) do
    base_name =
      base_theory_name
      |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
      |> String.trim("_")

    search_index =
      block_count
      |> Integer.to_string()
      |> String.pad_leading(3, "0")

    "#{base_name}_Search_#{search_index}"
  end

  defp template_path(mode) do
    @template_dir
    |> Path.join(template_file(mode))
  end

  defp template_file(:countermodels), do: "Countermodels.thy"
  defp template_file(:satisfying_models), do: "SatisfyingModels.thy"
  defp template_file(:consistency_check), do: "ConsistencyCheck.thy"

  defp read_template(path) do
    case File.read(path) do
      {:ok, source} ->
        {:ok, source}

      {:error, reason} ->
        {:error,
          {:cannot_read_search_theory_template,
            %{
              path: path,
              reason: reason
            }
          }
        }
    end
  end

  defp ensure_blocking_marker(source, path) do
    if String.contains?(source, @blocking_marker) do
      :ok
    else
      {:error,
        {:missing_blocking_marker,
          %{
            path: path,
            expected_marker: @blocking_marker
          }
        }
      }
    end
  end

  defp validate_blocking_axioms(blocking_axioms) do
    valid? =
      Enum.all?(
        blocking_axioms,
        fn axiom ->
          is_binary(axiom) and String.trim(axiom) != ""
        end
      )

    if valid? do
      :ok
    else
      {:error,
        {:invalid_blocking,
          blocking_axioms
        }
      }
    end
  end

  defp create_directory(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, reason} ->
        {:error,
          {:cannot_create_output_directory,
            %{
              path: path,
              reason: reason
            }
          }
        }
    end
  end

  defp write_theory(path, source) do
    case File.write(path, source) do
      :ok -> :ok

      {:error, reason} ->
        {:error,
          {:cannot_write_search_theory,
            %{
              path: path,
              reason: reason
            }
          }
        }
    end
  end
end
