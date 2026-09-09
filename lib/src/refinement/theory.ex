defmodule Src.Refinement.Theory do
  @moduledoc """
  Generates an Isabelle theory containing one structural refinement axiom.

  The generated theory import the unchanged base theory and adds
  the refinement axiom produced by `Src.Refinement.Axiom`. It can subsequently be
  used as the base theory of an ordinary `Src.Enumeration` run.

  Refinement axioms and model-specific blocking axioms remain separated:
  refinement axioms constrain the investigated theory, while blocking axioms
  only preventr repeated enumeration of already discovered models.
  """

  alias Src.Refinement.Axiom

  @typedoc "A JSON-decoded structural refinement candidate."
  @type candidate :: Axiom.candidate()

  @typedoc "An option controlling theory generation."
  @type option ::
          {:refinement_theory_dir, String.t()}
          | {:theory_name, String.t()}
          | {:axiom_name, String.t()}

  @typedoc "Options controlling theory generation."
  @type options :: [option()]

  @typedoc "A generated refined Isabelle theory."
  @type t :: %{
          theory_name: String.t(),
          theory_path: String.t(),
          base_theory_name: String.t(),
          base_theory_path: String.t(),
          candidate_id: String.t(),
          refinement_axiom: String.t()
        }

  @typedoc "An error encountered while generating a refined theory."
  @type write_error ::
          {:invalid_options, term()}
          | {:invalid_candidate, term()}
          | {:base_theory_not_found, String.t()}
          | {:invalid_base_theory_extension, String.t()}
          | {:missing_theory_declaration, String.t()}
          | {:theory_name_mismatch, map()}
          | {:invalid_theory_name, term()}
          | {:cannot_read_base_theory, map()}
          | {:cannot_create_refinement_directory, map()}
          | {:cannot_write_refinement_theory, map()}

  @doc """
  Writes a refined Isabelle theory importing `base_theory_path`.

  The generated theory contains exactly one structural refinement axiom.
  """
  @spec write(String.t(), candidate()) :: {:ok, t()} | {:error, write_error()}
  @spec write(String.t(), candidate(), options()) :: {:ok, t()} | {:error, write_error()}
  def write(base_theory_path, candidate, opts \\ []) do
    base_theory_path = Path.expand(base_theory_path)

    if File.regular?(base_theory_path) do
      candidate_id = Map.fetch!(candidate, "candidate_id")
      base_theory_name = Path.basename(base_theory_path, ".thy")

      default_theory_name =
        "#{base_theory_name}_Refined_#{candidate_id}"
        |> String.replace(~r/[^A-Za-z0-9_]+/, "_")

      theory_name =
        Keyword.get(opts, :theory_name, default_theory_name)

      theory_dir =
        opts
        |> Keyword.get(:refinement_theory_dir, Path.dirname(base_theory_path))
        |> Path.expand()

      axiom_opts =
        case Keyword.fetch(opts, :axiom_name) do
          {:ok, name} -> [name: name]
          :error -> []
        end

      refinement_axiom =
        Axiom.refinement_axiom(candidate, axiom_opts)

      theory_path =
        Path.join(theory_dir, "#{theory_name}.thy")

      base_import =
        relative_import(base_theory_path, theory_dir)

      source =
        """
        theory #{theory_name}
          imports "#{base_import}"
        begin

        #{refinement_axiom}

        end
        """

      case File.mkdir_p(theory_dir) do
        :ok ->
          case File.write(theory_path, source) do
            :ok ->
              {:ok,
               %{
                 theory_name: theory_name,
                 theory_path: theory_path,
                 base_theory_name: base_theory_name,
                 base_theory_path: base_theory_path,
                 candidate_id: candidate_id,
                 refinement_axiom: refinement_axiom
               }}

            {:error, reason} ->
              {:error, {:cannot_write_refinement_theory, %{path: theory_path, reason: reason}}}
          end

        {:error, reason} ->
          {:error, {:cannot_create_refinement_directory, %{path: theory_dir, reason: reason}}}
      end
    else
      {:error, {:base_theory_not_found, base_theory_path}}
    end
  end

  @spec relative_import(String.t(), String.t()) :: String.t()
  defp relative_import(base_theory_path, theory_dir) do
    path_parts =
      base_theory_path
      |> Path.rootname()
      |> Path.split()

    directory_parts =
      theory_dir
      |> Path.expand()
      |> Path.split()

    common_length =
      path_parts
      |> Enum.zip(directory_parts)
      |> Enum.take_while(fn {left, right} -> left == right end)
      |> length()

    relative_parts =
      List.duplicate(
        "..",
        length(directory_parts) - common_length
      ) ++ Enum.drop(path_parts, common_length)

    relative_parts
    |> Path.join()
    |> String.replace("\\", "/")
  end
end
