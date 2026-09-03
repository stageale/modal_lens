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
  @type option :: {:refinement_theory_dir, String.t()}
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
  @typed write_error :: {:invalid_options, term()}
                      | {:invalid_candidate, term()}
                      | {:base_theory_not_found, String.t()}
                      | {:invalid_base_theory_extension, String.t()}
                      | {:missing_theory_declaration, String.t()}
                      | {:theory_name_mismatch, map()}
                      | {:invalid_theory_name, term()}
                      | {:cannot_read_base_theory, map()}
                      | {:cannot_create_refinement_directory, map()}
                      | {:cannot_write_refinement_theory, map()}

  @option_keys [
    :refinement_theory_dir,
    :theory_name,
    :axiom_name
  ]

  @doc """
  Writes a refined Isabelle theory importing `base_theory_path`.

  The generated theory contains exactly one structural refinement axiom. Its
  directory default to the directory of the base theory and can be overridden
  with `:refinement_theory_dir`.
  The optional `:theory_name` and `:axiom_name` values override the generated
  Isabelle identifiers.
  """
  @spec write(String.t(), candidate()) :: {:ok, t()} | {:error, write_error()}
  @spec write(String.t(), candidate(), options()) :: {:ok, t()} | {:error, write_error()}
  def write(base_theory_path, candidate, opts \\ [])
  def write(base_theory_path, candidate, opts) when is_binary(base_theory_path) and is_map(candidate) and is_list(opts) do
    base_theory_path = Path.expand(base_theory_path)

    with :ok <- validate_options(opts),
        {:ok, base_theory_name} <- validate_base_theory(base_theory_path),
        {:ok, candidate_id} <- fetch_candidate_id(candidate),
        {:ok, theory_name} <- resolve_theory_name(
          base_theory_name,
          candidate_id,
          opts
        ),
        {:ok, refinement_axiom} <- render_axiom(candidate, opts),
        theory_dir =
          refinement_theory_dir(
            base_theory_path,
            opts
          ),
        :ok <- create_directory(theory_dir),
        theory_path =
          Path.join(theory_dir, "#{theory_name}.thy"),
          source =
            generate_source(
              theory_name,
              base_theory_path,
              theory_dir,
              refinement_axiom
            ),
          :ok <- write_theory(theory_path, source) do
            {:ok,
              %{
                theory_name: theory_name,
                theory_path: theory_path,
                base_theory_name: base_theory_name,
                base_theory_path: base_theory_path,
                candidate_id: candidate_id,
                refinement_axiom: refinement_axiom
              }
            }
          end
  end

  def write(base_theory_path, candidate, opts) do
    {:error,
      {:invalid_options,
        %{
          base_theory_path: base_theory_path,
          candidate: candidate,
          options: opts
        }
      }
    }
  end
  #TODO: Implement helpers
end
