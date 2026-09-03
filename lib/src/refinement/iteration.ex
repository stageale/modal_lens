defmodule Src.Refinement.Iteration do
  @moduledoc """
  Executes one structural refinement iteration.

  An iteration receives one selected refinement candidate, generates an
  Isabelle theory containing its refinement axiom, and starts a fresh model
  enumeration using that refined theory.

  Candidate selection and user interaction are handled by the caller. This
  module does not inspect cluster support or perform pattern mining.
  """

  alias Src.Enumeration
  alias Src.Refinement.Theory

  @typedoc "A JSON-decoded structural refinement candidate."
  @type candidate :: Selection.candidate()

  @typedoc "An option controlling one refinement iteration."
  @type option :: {:round, pos_integer()}
                | {:output_dir, String.t()}
                | {:selection, Selection.options()}
                | {:theory, Theory.options()}
                | {:enumeration, keyword()}

  @typedoc "Normalized configuration of one refinement iteration."
  @type configuration :: %{
    round: pos_integer(),
    output_dir: String.t(),
    theory: Theory.options(),
    enumeration: keyword()
  }

  @option_keys [
    :round,
    :output_dir,
    :theory,
    :enumeration
  ]

  #TODO: defstruct and t

  @enumeration_modes [
    :countermodels,
    :satisfying_models,
    :consistency_check
  ]

  @default_round 1
  @default_enumeration [mode: :countermodels]

  @doc """
  Applies one selected refinement candidate to `input_theory_path`.

  The function generates a refined Isabelle theory and enumerates models under
  that refinement. It does not select, rank, or assess the supplied candidate.

  Interactive callers should invoke this function only after explicit user
  acceptance. Automated benchmark callers may invoke it directly.
  """
  @spec run(String.t(), candidate()) :: {:ok, t()} | {:error, iteration_error()}
  @spec run(String.t(), candidate(), options())
  def run(input_theory_path, candidate, opts \\ [])
  def run(input_theory_path, candidate, opts) when is_binary(input_theory_path) and is_map(candidate) and is_list(opts) do
    input_theory_path = Path.expand(input_theory_path)
    with {:ok, configuration} <- normalize_options(input_theory_path, opts),
        {:ok, refined_theory} <- write_refined_theory(input_theory_path, candidate, configuration),
        {:ok, enumeration} <- enumerate_refined_theory(refined_theory.theory_path, configuration) do
          {:ok,
            %__MODULE__{
              round: configuration.round,
              input_theory_path: input_theory_path,
              output_dir: configuration.output_dir,
              selected_candidate: candidate,
              refined_theory: refined_theory,
              enumeration: enumeration
            }
          }
        end
  end

  def run(input_theory_path, candidate, opts) do
    {:error,
      {:invalid_options,
        %{
          input_theory_path: input_theory_path,
          candidate: candidate,
          options: opts
        }
      }
    }
  end

  @spec normalize_options(String.t(), options()) :: {:ok, configuration()} | {:error, iteration_error()}
  defp normalize_options(input_theory_path, opts) do
    if Keyword.keyword?(opts) do
      unknown_options =
        opts
        |> Keyword.keys()
        |> Enum.uniq()
        |> Kernel.--(@option_keys)

      if unknown_options == [] do
        build_configuration(input_theory_path, opts)
      else
        {:error,
          {:invalid_options,
            %{expected: :keyword_list, received: opts}
          }
        }
      end
    end
  end

  @spec build_configuration(String.t(), options()) :: {:ok, configuration()} | {:error, iteration_error()}
  defp build_configuration(input_theory_path, opts) do
    round =
      Keyword.get(opts, :round, @default_round)

    theory =
      Keyword.get(opts, :theory, [])

    enumeration =
      Keyword.get(opts, :enumeration, @default_enumeration)

    output_dir =
      Keyword.get(opts, :output_dir, default_output_dir(input_theory_path, round))

    with :ok <- validate_round(round),
        :ok <- validate_output_dir(output_dir),
        :ok <- validate_keyword_option(:theory, theory),
        :ok <- validate_keyword_option(:enumeration, enumeration),
        :ok <- validate_enumeration_mode(enumeration) do
          {:ok,
            %{
              round: round,
              output_dir: Path.expand(output_dir),
              theory: theory,
              enumeration: enumeration
            }
          }
        end
  end

  @spec write_refined_theory(String.t(), candidate(), configuration()) :: {:ok, Theory.t()} | {:error, iteration_error()}
  defp write_refined_theory(input_theory_path, candidate, configuration) do
    theory_opts =
      Keyword.put_new(configuration.theory, :refinement_theory_dir, Path.join(configuration.output_dir, "theory"))

    case Theory.write(input_theory_path, candidate, theory_opts) do
      {:ok, refined_theory} -> {:ok, refined_theory}
      {:error, reason} -> {:error, {:refinement_theory_failed, reason}}
    end
  end

  @spec enumerate_refined_theory(String.t(), configuration()) :: {:ok, map()} | {:error, iteration_error()}
  defp enumerate_refined_theory(refined_theory_path, configuration) do
    enumeration_output_dir =
      Path.join(configuration.output_dir, "enumeration")

    enumeration_opts =
      configuration.enumeration
      |> Keyword.put_new(:output_dir, enumeration_output_dir)
      |> Keyword.put_new(:search_theory_dir, Path.join(enumeration_output_dir, "search_theories"))

    case Enumeration.enumerate(refined_theory_path, enumeration_opts) do
      {:ok, enumeration} -> {:ok, enumeration}
      {:error, reason} -> {:error, {:refined_enumeration_failed, reason}}
    end
  end

  @spec validate_round(term()) :: :ok | {:error, iteration_error()}
  defp validate_round(round) when is_integer(round) and round > 0, do: :ok
  defp validate_round(round) do
    {:error,
      {:invalid_options,
        %{option: :round, received: round}
      }
    }
  end

  @spec validate_output_dir(term()) :: :ok | {:error, iteration_error()}
  defp validate_output_dir(output_dir) when is_binary(output_dir) do
    if String.trim(output_dir) == "" do
      {:error,
        {:invalid_options,
          %{option: :output_dir, received: output_dir}
        }
      }
    else
      :ok
    end
  end

  defp validate_output_dir(output_dir) do
    {:error,
      {:invalid_options,
        %{option: :output_dir, received: output_dir}
      }
    }
  end

  @spec validate_keyword_option(atom(), term()) :: :ok | {:error, iteration_error()}
  defp validate_keyword_option(name, value) do
    if Keyword.keyword?(value) do
      :ok
    else
      {:error,
        {:invalid_options,
          %{option: name, received: value}
        }
      }
    end
  end

  @spec validate_enumeration_mode(keyword()) :: :ok | {:error, iteration_error()}
  defp validate_enumeration_mode(opts) do
    case Keyword.fetch(opts, :mode) do
      {:ok, mode} when mode in @enumeration_modes -> :ok
      {:ok, mode} -> {:error, {:invalid_options, %{option: :mode, received: mode}}}
      :error -> {:error, {:invalid_options, %{option: enumeration, missing: :mode}}}
    end
  end

  @spec default_output_dir(String.t(), pos_integer()) :: String.t()
  defp default_output_dir(input_theory_path, round) do
    base_name =
      input_theory_path
      |> Path.basename(".thy")
      |> String.replace(~r/[^A-Za-z0-9_-]+/, "_")
      |> String.trim("_")

    round_name =
      round
      |> Integer.to_string()
      |> String.pad_leading(3, "0")
      |> then(&"round_#{&1}")

    Path.join([
      "out",
      "#{base_name}_refinement",
      round_name
    ])
  end
end
