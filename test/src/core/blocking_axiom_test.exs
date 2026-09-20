defmodule Src.Core.BlockingAxiomTest do
  use ExUnit.Case, async: true

  alias Src.Core.BlockingAxiom
  alias Src.Core.Model.DDL
  alias Src.Core.Model.EDSTIT, as: EDSTITModel
  alias Src.Core.Model.Modality
  alias Src.Core.Model.SDL

  defp sdl_model do
    %SDL{
      source: "examples/input/chisholm-a1.txt",
      kind: :countermodel,
      cardinality: 2,
      relation_name: "R",
      initial_world: 1,
      edges: MapSet.new([{0, 1}]),
      valuations: %{"go" => [true, false]}
    }
  end

  test "sanitizes Isabelle-compatible names" do
    assert BlockingAxiom.sanitize_name("chisholm_a1") == "chisholm_a1"
    assert BlockingAxiom.sanitize_name("chisholm-a1.txt") == "chisholm_a1_txt"
    assert BlockingAxiom.sanitize_name("123 bad name") == "m_123_bad_name"
    assert BlockingAxiom.sanitize_name("!!!") == "nitpick_model"
  end

  test "extracts a source stem and uses a fallback for text input" do
    assert BlockingAxiom.source_stem(sdl_model()) == "chisholm-a1"
    assert BlockingAxiom.source_stem(%SDL{sdl_model() | source: nil}) == "nitpick_model"
  end

  test "renders the complete finite SDL structure" do
    formula = BlockingAxiom.exact_structure_formula(sdl_model())

    assert formula =~ ~S|\<exists>u1 u2.|
    assert formula =~ "distinct [u1, u2]"
    assert formula =~ ~S|(\<forall>x. x = u1 \<or> x = u2)|
    assert formula =~ ~S|\<not>(R u1 u1)|
    assert formula =~ "(R u1 u2)"
    assert formula =~ "(go u1)"
    assert formula =~ ~S|\<not>(go u2)|
    refute formula =~ "actual_world ="
  end

  test "can include the designated world with logic-specific constants" do
    sdl_formula =
      BlockingAxiom.exact_structure_formula(sdl_model(),
        include_designated_world: true
      )

    assert sdl_formula =~ "(actual_world = u2)"

    ddl_model = %DDL{
      kind: :model,
      cardinality: 1,
      relation_name: "R",
      actual_world: 0,
      edges: MapSet.new(),
      valuations: %{}
    }

    ddl_formula =
      BlockingAxiom.exact_structure_formula(ddl_model,
        include_designated_world: true,
        designated_world_constant: "aw"
      )

    assert ddl_formula =~ "(aw = u1)"
  end

  test "renders ED-STIT modalities with quantified active agents" do
    model = %EDSTITModel{
      kind: :countermodel,
      cardinality: 2,
      actual_world: 0,
      agents: ["provider"],
      modalities: [
        Modality.new!("RBox", :settledness, [{0, 0}, {0, 1}]),
        Modality.new!("RStit", :stit, [{0, 1}], agent: "provider"),
        Modality.new!("ROught", :ought, [{1, 1}], agent: "provider"),
        Modality.new!("RBel", :belief, [{0, 1}], agent: "provider")
      ],
      valuations: %{"p" => [true, false]}
    }

    formula = BlockingAxiom.exact_structure_formula(model)

    assert formula =~ ~S|\<exists>u1 u2 a1.|
    assert formula =~ "(Agent a1)"
    assert formula =~ "(RBox u1 u2)"
    assert formula =~ "(RStit a1 u1 u2)"
    assert formula =~ "(ROught a1 u2 u2)"
    assert formula =~ "(RBel a1 u1 u2)"
    assert formula =~ ~S|\<not>(RStit a1 u1 u1)|
    refute formula =~ ~S|\<forall>a.|
  end

  test "wraps the negated structure as a named axiom" do
    axiom = BlockingAxiom.blocking_axiom(sdl_model(), name: "model-1")

    assert axiom =~ "axiomatization where"
    assert axiom =~ ~S|ax_model_1: "\<not>(|
    assert axiom =~ ~S|\<exists>u1 u2.|
  end

  test "falls back to the source name when name is explicitly nil" do
    axiom = BlockingAxiom.blocking_axiom(sdl_model(), name: nil)
    assert axiom =~ "ax_chisholm_a1:"
  end

  test "rejects malformed valuations and invalid designated worlds" do
    bad_values = %SDL{sdl_model() | valuations: %{"go" => [true]}}

    assert_raise ArgumentError, ~r/valuation "go"/, fn ->
      BlockingAxiom.exact_structure_formula(bad_values)
    end

    bad_world = %SDL{sdl_model() | initial_world: 3}

    assert_raise ArgumentError, ~r/designated world 3/, fn ->
      BlockingAxiom.exact_structure_formula(bad_world)
    end
  end
end
