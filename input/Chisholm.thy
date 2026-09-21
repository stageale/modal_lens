theory Chisholm
  imports Main
begin

section \<open>Standard Deontic Logic\<close>

typedecl i
type_synonym sigma = "i \<Rightarrow> bool"

consts
  R :: "i \<Rightarrow> i \<Rightarrow> bool"
  actual_world :: i

definition mnot :: "sigma \<Rightarrow> sigma" where
  "mnot \<phi> = (\<lambda>w. \<not> \<phi> w)"

definition mimp :: "sigma \<Rightarrow> sigma \<Rightarrow> sigma" where
  "mimp \<phi> \<psi> = (\<lambda>w. \<phi> w \<longrightarrow> \<psi> w)"

definition box :: "sigma \<Rightarrow> sigma" where
  "box \<phi> = (\<lambda>w. \<forall>v. R w v \<longrightarrow> \<phi> v)"

abbreviation obligation :: "sigma \<Rightarrow> sigma" ("O _" [52] 53) where
  "O \<phi> \<equiv> box \<phi>"

definition holds_at_actual :: "sigma \<Rightarrow> bool" where
  "holds_at_actual \<phi> \<longleftrightarrow> \<phi> actual_world"


section \<open>SDL frame condition\<close>

axiomatization where
  seriality: "\<forall>w. \<exists>v. R w v"


section \<open>Chisholm scenario\<close>

consts
  go :: sigma
  tell :: sigma

text \<open>
  go means that Jones goes to help his neighbours.
  tell means that Jones tells them that he is coming.
\<close>

axiomatization where
  chisholm_1:
    "holds_at_actual (O go)"
and
  chisholm_2:
    "holds_at_actual (mimp go (O tell))"
and
  chisholm_3:
    "holds_at_actual (mimp (mnot go) (O (mnot tell)))"
and
  chisholm_4:
    "holds_at_actual (mnot go)"


section \<open>Derived contrary-to-duty obligation\<close>

lemma contrary_to_duty_obligation:
  "holds_at_actual (O (mnot tell))"
  using chisholm_3 chisholm_4
  unfolding holds_at_actual_def mimp_def mnot_def
  by simp


section \<open>Axiom Refiner query\<close>

abbreviation axiom_refiner_query :: bool where
  "axiom_refiner_query \<equiv> holds_at_actual (O tell)"

end