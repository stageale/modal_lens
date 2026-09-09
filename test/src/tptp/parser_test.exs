defmodule Src.TPTP.ParserTest do
  use ExUnit.Case, async: true

  alias Src.TPTP.AnnotatedFormula
  alias Src.TPTP.Document
  alias Src.TPTP.Include
  alias Src.TPTP.Parser

  test "parses THF formulae without interpreting their bodies" do
    input = """
    thf(person_type,type,(person:$tType)).
    thf(p_type,type,(p:person>$o)).
    thf(ax,axiom,(p @ a)).
    thf(goal,conjecture,(? [X:person] : (p @ X))).
    """

    assert {:ok, document} = Parser.parse(input, source: "example.p")
    assert document.source == "example.p"

    assert [
             %AnnotatedFormula{name: "person_type", role: :type},
             %AnnotatedFormula{name: "p_type", role: :type},
             %AnnotatedFormula{name: "ax", role: :axiom},
             %AnnotatedFormula{name: "goal", role: :conjecture, formula: formula}
           ] = Document.formulas(document)

    assert formula == "(? [X:person] : (p @ X))"
  end

  test "preserves nested commas in formulae and annotations" do
    input = """
    thf(step,plain,(f @ (g @ a) @ (h @ b)),inference(foo,[status(thm)],[ax1,ax2]),[useful('a,b')]).
    """

    assert {:ok, document} = Parser.parse(input)
    [formula] = Document.formulas(document)

    assert formula.formula == "(f @ (g @ a) @ (h @ b))"
    assert formula.source == "inference(foo,[status(thm)],[ax1,ax2])"
    assert formula.useful_info == "[useful('a,b')]"
  end

  test "ignores line and block comments without treating comment markers inside quotes as comments" do
    input = """
    % ordinary line comment
    thf(a,axiom,('literal%value' = 'literal%value')).
    /* ordinary block comment */
    thf(c,conjecture,$true).
    """

    assert {:ok, document} = Parser.parse(input)
    assert Enum.map(Document.formulas(document), & &1.name) == ["a", "c"]
  end

  test "parses include directives with default and explicit selections" do
    input = """
    include('Axioms/SET001.ax').
    include('Axioms/SET002.ax',[ax1,'ax two',42]).
    thf(goal,conjecture,$true).
    """

    assert {:ok, document} = Parser.parse(input)

    assert [
             %Include{file: "Axioms/SET001.ax", selection: :all},
             %Include{
               file: "Axioms/SET002.ax",
               selection: ["ax1", "'ax two'", "42"]
             }
           ] = Document.includes(document)
  end

  test "preserves lexically distinct TPTP names" do
    input = """
    thf(123,axiom,$true).
    thf('123',axiom,$true).
    """

    assert {:ok, document} = Parser.parse(input)
    assert Enum.map(Document.formulas(document), & &1.name) == ["123", "'123'"]
  end

  test "accepts whitespace between THF keyword and opening parenthesis" do
    assert {:ok, document} = Parser.parse("thf (a,axiom,$true).")
    assert [%AnnotatedFormula{name: "a"}] = Document.formulas(document)
  end

  test "reports unsupported top-level constructs" do
    assert {:error, {:unsupported_construct, _}} = Parser.parse("fof(a,axiom,$true).")
  end

  test "reports invalid roles" do
    assert {:error, {:invalid_role, "made_up_role"}} =
             Parser.parse("thf(a,made_up_role,$true).")
  end

  test "reports unterminated statements" do
    assert {:error, {:unterminated_statement, _}} =
             Parser.parse("thf(a,axiom,$true)")
  end

  test "parse_file records the source path" do
    path =
      Path.join(
        System.tmp_dir!(),
        "modal_lens_tptp_#{System.unique_integer([:positive])}.p"
      )

    File.write!(path, "thf(a,axiom,$true).\n")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, document} = Parser.parse_file(path)
    assert document.source == path
  end
end
