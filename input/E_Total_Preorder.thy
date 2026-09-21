theory E_Total_Preorder
  imports E
begin

section \<open>Total-preorder preference models\<close>

text \<open>
  For the finite preference models considered in our experiments,
  the betterness relation R is assumed to be total and transitive.

  These are additional frame assumptions on the models under
  investigation. They are not part of the definition of optimality
  in System E.
\<close>

axiomatization where
  R_total:
    "\<forall>x y. x R y \<or> y R x"
and
  R_transitive:
    "\<forall>x y z. x R y \<and> y R z \<longrightarrow> x R z"


text \<open>
  Totality implies reflexivity, hence R is a total preorder.
\<close>

lemma R_reflexive:
  "\<forall>x. x R x"
  using R_total
  by blast


text \<open>
  Sanity check: the selected frame conditions are jointly satisfiable.
\<close>

lemma True
  nitpick [satisfy, user_axioms, expect=genuine]
  oops

end