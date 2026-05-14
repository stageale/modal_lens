defmodule Formula do
  defstruct [:kind, :args]

  def neg(phi), do: "¬(#{phi})"
  def conj(phi, psi), do: "#{phi} ∧ #{psi}"
  def disj(phi, psi), do: "#{phi} ∨ #{psi}"
  def impl(phi, psi), do: "#{phi} ⟶ #{psi}"
  def box(r, phi), do: "□\\<^sub>#{r}#{phi}"

  def axiom(name, body) do
    ~s/axiomatization where #{name}: "#{body}"/
  end

  def edge_formula({i, j}) do
    "r w#{i} w#{j}"
  end
end
