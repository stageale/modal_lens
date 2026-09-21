theory Dyadic_Chisholm
  imports E_Total_Preorder
begin


section \<open>Dyadic deontic logic\<close>

text \<open>
  The embedding E calls the actual world aw.  Axiom Refiner uses the
  uniform name actual_world when generating blocking axioms.
\<close>

abbreviation actual_world :: i where
  "actual_world \<equiv> aw"


section \<open>Chisholm scenario\<close>

consts
  go   :: \<sigma>
  tell :: \<sigma>

text \<open>Jones ought to go and assist his neighbours.\<close>

abbreviation D1 :: \<sigma> where
  "D1 \<equiv> \<circle><go|\<^bold>\<top>>"


text \<open>If Jones goes, he ought to tell them that he is coming.\<close>

abbreviation D2 :: \<sigma> where
  "D2 \<equiv> \<circle><tell|go>"


text \<open>If Jones does not go, he ought not tell them.\<close>

abbreviation D3 :: \<sigma> where
  "D3 \<equiv> \<circle><\<^bold>\<not>tell|\<^bold>\<not>go>"


text \<open>Jones does not go in the actual world.\<close>

abbreviation D4 :: \<sigma> where
  "D4 \<equiv> \<^bold>\<not>go"


section \<open>Normative theory\<close>

axiomatization where
  chisholm_1: "\<lfloor>D1\<rfloor>"
and
  chisholm_2: "\<lfloor>D2\<rfloor>"
and
  chisholm_3: "\<lfloor>D3\<rfloor>"
and
  chisholm_4: "\<lfloor>D4\<rfloor>\<^sub>l"

section \<open>Axiom Refiner query\<close>

abbreviation axiom_refiner_query :: bool where
  "axiom_refiner_query \<equiv>
     \<lfloor>\<^bold>\<circle><\<^bold>\<not>tell>\<rfloor>\<^sub>l"

end