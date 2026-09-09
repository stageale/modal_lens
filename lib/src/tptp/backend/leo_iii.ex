defmodule Src.TPTP.Backend.Leo3 do
  @moduledoc """
  Executes Leo-III on TPTP problems and exposes its SZS result.

  The backend preserves the prover output and optional proof certificate
  for subsequent semantic analysis and verbalization.
  """

  alias Src.TPTP.SZS

  @typedoc """
  Option controlling a Leo-III invocation.
  """
  @type option :: {:executable, String.t()}
                | {:timeout, non_neg_integer()}
                | {:proof, boolean()}
                | {:extra_args, [String.t()]}

  @typedoc """
  Result of a completed Leo-III invocation.
  """
  @type result :: %{
    backend: :leo_iii,
    problem: String.t(),
    status: SZS.status(),
    exit_status: non_neg_integer(),
    output: String.t(),
    proof: String.t() | nil
  }

  @typedoc """
  Error occuring before a usable Leo-III result could be obtained.
  """
  @type run_error :: {:executable_not_found, String.t()}
                   | {:szs_error, SZS.parse_error(), String.t()}

  @doc """
  Runs Leo-III on a TPTP problem.

  Proof ouptut is requested by default so that successful reasoning
  results can later be used as formal explanation evidence.
  """
  @spec run(String.t(), [option()]) :: {:ok, result()} | {:error, run_error()}
  def run(problem, opts \\ []) when is_binary(problem) do
    executable = Keyword.get(opts, :executable, "leo3")
    args = build_args(problem, opts)

    try do
      {output, exit_status} =
        System.cmd(executable, args, stderr_to_stdout: true)

      case SZS.parse(output) do
        {:ok, status} ->
          {:ok,
            %{
              backend: :leo_iii,
              problem: problem,
              status: status,
              exit_status: exit_status,
              output: output,
              proof: extract_proof(output)
            }
          }

        {:error, reason} -> {:error, {:szs_error, reason, output}}
      end
    rescue
      error in ErlangError ->
        case error.original do
          :enoent -> {:error, {:executable_not_found, executable}}
          _ -> reraise error, __STACKTRACE__
        end
    end
  end

  @spec build_args(String.t(), [option()]) :: [String.t()]
  defp build_args(problem, opts) do
    timeout = Keyword.get(opts, :timeout, 60)
    proof? = Keyword.get(opts, :proof, true)
    extra_args = Keyword.get(opts, :extra_args, [])

    [problem, "-t", Integer.to_string(timeout)]
    |> maybe_add_proof(proof?)
    |> Kernel.++(extra_args)
  end

  @spec maybe_add_proof([String.t()], boolean()) :: [String.t()]
  defp maybe_add_proof(args, true), do: args ++ ["-p"]
  defp maybe_add_proof(args, false), do: args

  @spec extract_proof(String.t()) :: String.t() | nil
  defp extract_proof(output) do
    case Regex.run(~r/%\s*SZS\s+output\s+(?:start|begin)[^\n]*\n(.*?)%\s*SZS\s+output\s+end[^\n]*/s, output, capture: :all_but_first) do
      [proof] -> String.trim(proof)
      nil -> nil
    end
  end
end
