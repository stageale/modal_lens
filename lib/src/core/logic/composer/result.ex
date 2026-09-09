defmodule Src.Core.Logic.Composer.Result do
  @moduledoc """
  Compiles a declarative `Spec` into a language and derived model class.

  The intended pipeline is:

    1. validate fragments and bridges;
    2. resolve and order declared dependencies;
    3. combine types, signatures, and binding operators;
    4. apply explicit bridge mappings;
    5. assemble semantic and proof-theoretic constraints;
    6. propagate uniquely determined semantic choices;
    7. emit unresolved choices, diagnostics, and proof obligations.

  The Composer is deterministic and has no interactive dependencies. A CLI or
  UI may consume an incomplete `Draft`, amend the `Spec`, and invoke it again.
  """

  alias Src.Core.Logic.Composer.CompiledLogic
  alias Src.Core.Logic.Composer.Diagnostic
  alias Src.Core.Logic.Composer.Draft
  alias Src.Core.Logic.Spec

  @type mode :: :strict | :infer
  @type compile_option :: {:mode, mode()} | {atom(), term()}

  @type result :: {:ok}
                | {:incomplete, Draft.t()}
                | {:error, [Diagnostic.t()]}

  @doc """
  Compiles one specification determinstically.

  `:strict` rejects every unresolved choice. `:infer` may return an incomplete
  draft after propagating  all uniquely determined consequences. Neither mode
  invents bridges or selects between inequivalent semantics.
  """
  @spec compile(Spec.t(), [compile_option()]) :: result()
  def compile(_spec, _options \\ []) do
    raise "Src.Core.Logic.Composer.compile/2 is not implemented"
  end

  @doc """
  Enumerates bounded complete variants of a specification.
  This operation is intended for controlled logic experimentation. Limits and
  admissible choice dimensions must be supplied explicitly to prevent an
  accidental combinatorial explosion.
  """
  @spec variants(Spec.t(), keyword()) :: {:ok, [CompiledLogic.t()]}
                                       | {:incomplete, Draft.t()}
                                       | {:error, [Diagnostic.t()]}
  def variants(_spec, _opts \\ []) do
    raise "Src.Core.Logic.Composer.variants/2 is not implemented."
  end
end
defmodule Src.Core.Logic.Composer.Choice do
  @moduledoc """
  Describes one genuine semantic or compositional choice left unresolved.

  Interactive clients may present this data to a user. Batch clients must add
  a corresponding decision to the specification before recompiling.
  """

  @type t :: %__MODULE__{
          key: term(),
          alternatives: [term()],
          reason: String.t(),
          provenance: [term()]
        }

  @enforce_keys [:key, :alternatives, :reason]
  defstruct key: nil,
            alternatives: [],
            reason: nil,
            provenance: []
end

defmodule Src.Core.Logic.Composer.Diagnostic do
  @moduledoc """
  Reports a structural error, warning, or informational composition fact.
  """

  @type severity :: :error | :warning | :info

  @type t :: %__MODULE__{
          severity: severity(),
          code: atom(),
          message: String.t(),
          details: term(),
          provenance: [term()]
        }

  @enforce_keys [:severity, :code, :message]
  defstruct severity: nil,
            code: nil,
            message: nil,
            details: nil,
            provenance: []
end

defmodule Src.Core.Logic.Composer.Obligation do
  @moduledoc """
  Describes a mathematical claim that composition cannot decide structurally.

  Examples include consistency, monotonicity, soundness, completeness, and
  faithfulness obligations intended for Isabelle/HOL or another backend.
  """

  @type status :: :open | :discharged | :failed

  @type t :: %__MODULE__{
          key: term(),
          kind: atom(),
          statement: term(),
          status: status(),
          backend_hint: term() | nil,
          provenance: [term()]
        }

  @enforce_keys [:key, :kind, :statement]
  defstruct key: nil,
            kind: nil,
            statement: nil,
            status: :open,
            backend_hint: nil,
            provenance: []
end

defmodule Src.Core.Logic.Composer.Draft do
  @moduledoc """
  Holds a normalized but semantically incomplete composition result.
  """

  alias Src.Core.Logic.Composer.Choice
  alias Src.Core.Logic.Composer.Diagnostic
  alias Src.Core.Logic.Composer.Obligation
  alias Src.Core.Logic.Language
  alias Src.Core.Logic.ProofSystem
  alias Src.Core.Logic.Semantics.ModelClass

  @type t :: %__MODULE__{
          language: Language.t() | nil,
          model_class: ModelClass.t() | nil,
          proof_system: ProofSystem.t() | nil,
          choices: [Choice.t()],
          obligations: [Obligation.t()],
          diagnostics: [Diagnostic.t()],
          provenance: map()
        }

  defstruct language: nil,
            model_class: nil,
            proof_system: nil,
            choices: [],
            obligations: [],
            diagnostics: [],
            provenance: %{}
end

defmodule Src.Core.Logic.Composer.CompiledLogic do
  @moduledoc """
  Represents a complete, normalized logic ready for backend compilation.

  The structure retains its source specification and every remaining proof
  obligation so generated Isabelle theories stay reproducible and auditable.
  """

  alias Src.Core.Logic.Composer.Diagnostic
  alias Src.Core.Logic.Composer.Obligation
  alias Src.Core.Logic.Lang
  alias Src.Core.Logic.ProofSystem
  alias Src.Core.Logic.Semantics.ModelClass
  alias Src.Core.Logic.Spec

  @type t :: %__MODULE__{
          name: String.t(),
          source_spec: Spec.t(),
          language: Lang.t(),
          model_class: ModelClass.t(),
          proof_system: ProofSystem.t(),
          obligations: [Obligation.t()],
          diagnostics: [Diagnostic.t()],
          provenance: map()
        }

  @enforce_keys [
    :name,
    :source_spec,
    :language,
    :model_class,
    :proof_system
  ]

  defstruct name: nil,
            source_spec: nil,
            language: nil,
            model_class: nil,
            proof_system: nil,
            obligations: [],
            diagnostics: [],
            provenance: %{}
end
