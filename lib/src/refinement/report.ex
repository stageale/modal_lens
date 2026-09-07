defmodule Src.Refinement.Report do
  @moduledoc """
  Builds the deterministic reportof a completed structural refinement loop.

  The report records applied candidates, generated Isabelle axioms, and the
  observed model counts before and after every refinement. Model-count changes
  describe the bounded enumeration runs and are not interpreted as global
  logical model counts.
  """

  alias Src.Refinement.Loop

  @schema "modal-lens/refinement-report"
  @schema_version "1.0"

  @typedoc "A JSON-compatible report of one completed refinement loop."
  @type t :: %{required(String.t()) => term()}

  @typedoc "An error encountered while writing the refinement report."
  @type write_error :: {:cannot_encode_refinement_report, term()}
                     | {:cannot_write_refinement_report, String.t(), term()}

  @doc """
  Projects a completed refinement loop onto its JSON-compatible report.

  Every iteration contains the candidate and axiom actually applied together
  with the status and model count of the adjacent bounded enumerations.
  """
  @spec to_map(Loop.t()) :: t()
  def to_map(%Loop{} = loop) do
    initial_enumeration = %{
      "status" =>
        loop.initial_pipeline_result
        |> Map.fetch!(:status)
        |> Atom.to_string(),
      "model_count" =>
        Map.get(loop.initial_pipeline_result, :model_count, 0)
    }

    {iterations, _final_model_count} =
      Enum.map_reduce(loop.iterations, initial_enumeration, fn iteration, enumeration_before ->
        candidate = iteration.selected_candidate
        origin = candidate["origin"]

        enumeration_after = %{
          "status" =>
            iteration.pipeline_result
            |> Map.fetch!(:status)
            |> Atom.to_string(),
          "model_count" =>
            Map.get(iteration.pipeline_result, :model_count, 0)
        }

        report = %{
          "round" => iteration.round,
          "input_theory_path" => iteration.input_theory_path,
          "refined_theory_path" => iteration.refined_theory.theory_path,
          "run_id" => iteration.run.id,
          "output_dir" => iteration.run.output_dir,
          "candidate" => candidate,
          "candidate_id" => candidate["candidate_id"],
          "pattern_id" => origin["pattern_id"],
          "cluster_id" => origin["cluster_id"],
          "cluster_support" => origin["cluster_support"],
          "outside_support" => origin["outside_support"],
          "graphlet_size" => candidate["occurrence"]["size"],
          "refinement_axiom" => iteration.refined_theory.refinement_axiom,
          "enumeration_before" => enumeration_before,
          "enumeration_after" => enumeration_after,
        }

        {report, enumeration_after}
      end)

    final_enumeration = %{
      "status" =>
        loop.final_pipeline_result
        |> Map.fetch!(:status)
        |> Atom.to_string(),
      "model_count" =>
        Map.get(loop.final_pipeline_result, :model_count, 0)
    }

    %{
      "schema" => @schema,
      "schema_version" => @schema_version,
      "status" => "completed",
      "stop_reason" => Atom.to_string(loop.stop_reason),
      "applied_refinement_count" => length(iterations),
      "initial" => %{
        "theory_path" => loop.initial_theory_path,
        "run_id" => loop.initial_run.id,
        "output_dir" => loop.initial_run.output_dir,
        "enumeration" => initial_enumeration
      },
      "iteration" => iterations,
      "final" => %{
        "theory_path" => loop.final_theory_path,
        "run_id" => loop.final_run.id,
        "output_dir" => loop.final_run.output_dir,
        "enumeration" => final_enumeration
      }
    }
  end

  @doc """
  Writes the rport as formatted JSON.

  By default, `refinement.json` is written into the initial run directory.
  """
  @spec write(Loop.t()) :: {:ok, String.t()} | {:error, write_error()}
  @spec write(Loop.t(), String.t()) :: {:ok, String.t()} | {:error, write_error()}
  def write(%Loop{} = loop, path \\ nil) do
    report_path =
      path ||
        Path.join(loop.initial_run.output_dir, "refinement.json")
      |> Path.expand()

    with {:ok, json} <- Jason.encode(to_map(loop), pretty: true),
          :ok <- File.mkdir_p(Path.dirname(report_path)),
          :ok <- File.write(report_path, json <> "\n") do
            {:ok, report_path}
          else
            {:error, %Jason.EncodeError{} = reason} ->
              {:error,
                {:cannot_encode_refinement_report,
                  reason
                }
              }
            {:error, reason} ->
              {:error,
                {:cannot_write_refinement_report,
                  report_path,
                  reason
                }
              }
          end
  end
end
