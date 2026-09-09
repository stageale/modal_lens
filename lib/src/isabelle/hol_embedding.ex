defmodule Src.Isabelle.HOLEmbedding do
  @moduledoc """
  Generates Isabelle/HOL theories for generated reasoning tasks.

  The module translates an embedding specification into Isabelle theory
  and ROOT files that can be executed through `Src.Isabelle.Client`.
  """

  defstruct theory_name: "Modal_Lens_Run",
            imports: ["Main"],
            type_name: "i",
            relation_name: "r",
            atoms: [],
            axioms: [],
            goal: "False",
            nitpick_options: ["user_axioms"]

  def new(opts \\ []) do
    struct!(__MODULE__, opts)
  end

  def render_theory(%__MODULE__{} = spec) do
    """
    theory #{spec.theory_name}
      imports #{Enum.join(spec.imports, " ")}
    begin

    #{render_base_signature(spec)}
    #{render_frame_axiom_definitions(spec)}
    #{render_atoms(spec)}
    #{render_axioms(spec)}

    lemma generated_reasoning_goal:
      "#{spec.goal}"
      nitpick [#{Enum.join(spec.nitpick_options, ", ")}]
      oops

    end
    """
  end

  def write_theory!(%__MODULE__{} = spec, dir) do
    File.mkdir_p!(dir)

    path = Path.join(dir, "#{spec.theory_name}.thy")
    File.write!(path, render_theory(spec))

    path
  end

  def write_root!(%__MODULE__{} = spec, dir) do
    File.mkdir_p!(dir)

    path = Path.join(dir, "ROOT")

    File.write!(path, """
    session #{spec.theory_name} = HOL +
      theories
        #{spec.theory_name}
    """)

    path
  end

  defp render_base_signature(spec) do
    """
    typedecl #{spec.type_name}

    consts #{spec.relation_name} :: "#{spec.type_name} \\<Rightarrow> #{spec.type_name} \\<Rightarrow> bool"
    """
  end

  defp render_atoms(spec) do
    spec.atoms
    |> Enum.map(fn atom -> ~s|consts #{atom} :: "#{spec.type_name} \\<Rightarrow> bool"| end)
    |> Enum.join("\n")
  end

  defp render_axioms(spec) do
    spec.axioms
    |> Enum.with_index(1)
    |> Enum.map(fn {formula, i} ->
      """
      axiomatization where ax_generated_#{i}:
        "#{formula}"
      """
    end)
    |> Enum.join("\n")
  end

  defp render_frame_axiom_definitions(spec) do
    r_type = "#{spec.type_name} \\<Rightarrow> #{spec.type_name} \\<Rightarrow> bool"

    """
    definition serial :: "(#{r_type}) \\<Rightarrow> bool" where
      "serial R \\<longleftrightarrow> (\\<forall>w. \\<exists>v. R w v)"

    definition reflexive :: "(#{r_type}) \\<Rightarrow> bool" where
      "reflexive R \\<longleftrightarrow> (\\<forall>w. R w w)"

    definition symmetric :: "(#{r_type}) \\<Rightarrow> bool" where
      "symmetric R \\<longleftrightarrow> (\\<forall>w v. R w v \\<longrightarrow> R v w)"

    definition transitive :: "(#{r_type}) \\<Rightarrow> bool" where
      "transitive R \\<longleftrightarrow> (\\<forall>w v u. R w v \\<and> R v u \\<longrightarrow> R w u)"

    definition euclidean :: "(#{r_type}) \\<Rightarrow> bool" where
      "euclidean R \\<longleftrightarrow> (\\<forall>w v u. R w v \\<and> R w u \\<longrightarrow> R v u)"

    definition functional :: "(#{r_type}) \\<Rightarrow> bool" where
      "functional R \\<longleftrightarrow> (\\<forall>w v u. R w v \\<and> R w u \\<longrightarrow> v = u)"
    """
  end

  def frame_axiom(r \\ "r", kind)

  def frame_axiom(r, :serial), do: "serial #{r}"
  def frame_axiom(r, :reflexive), do: "reflexive #{r}"
  def frame_axiom(r, :symmetric), do: "symmetric #{r}"
  def frame_axiom(r, :transitive), do: "transitive #{r}"
  def frame_axiom(r, :euclidean), do: "euclidean #{r}"
  def frame_axiom(r, :functional), do: "functional #{r}"
end
