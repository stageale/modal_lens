theory Chisholm_DDL
    imports
begin

consts
    go      :: \<tau>
    tell    :: \<tau>

text \<open>Jones ought to go and assist his neighbours.\<close>

abbreviation D1 :: \<tau> where
    "D1 \<equiv>
        \<circle><go|<^bold>\<top>>"

    
text \<open>If Jones goes, he ought to tell them that he is coming.\<close>

abbreviation D2 :: \<tau> where
    "D2 \<equiv>
        \<circle><tell|go>"


text \<open>If Jones does not go, he ought not tell them.\<close>

abbreviation D3 :: \<tau> where
    "D3 \<equiv> \<circle>\<^bold>\<not>tell|\<^bold>\<not>go>"


text \<open>Jones does not go in the actual world.\<close>

abbreviation D4 :: \<tau> where
    "D4 \<equiv> \<^bold>\<not> go"
end

section \<open>Normative theory\<close>

axiomatization where
  chisholm_1: "\<lfloor>D1\<rfloor>"
and
  chisholm_2: "\<lfloor>D2\<rfloor>"
and
  chisholm_3: "\<lfloor>D3\<rfloor>"
and
  chisholm_4: "\<lfloor>D4\<rfloor>\<^sub>l"


(* MODAL_LENS_BLOCKS *)


section \<open>Nitpick target\<close>

lemma detached_contrary_to_duty_obligation:
  "\<lfloor>\<^bold>\<circle><\<^bold>\<not>tell>\<rfloor>\<^sub>l"
  nitpick [
    user_axioms,
    card i = 2,
    timeout = 60,
    verbose,
    show_consts,
    dont_specialize,
    format = 2
  ]
  oops

end