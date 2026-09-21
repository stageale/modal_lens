theory AIAct_Article20_DDL
    imports E_Total_Preorder
begin

section \<open>Article 20 CTD abstraction\<close>

text \<open>
    This theory isolates the contrary-to-duty structure of Article 20(1)
    of the European AI Act.

    The actual legal provision refers to the provider considering, or 
    having reason to consider, that a high-risk AI system is not in 
    conformity. That epistemic component is deliberately abstracted
    away here and will be represented separately in the epistemic
    deontic STIT case study.
\<close>


section \<open>Actual world\<close>

text \<open>
    ModalLens uses the uniform name actual_world when generating
    model-specific blocking axioms.
\<close>

abbreviation actual_world :: i where
    "actual_world \<equiv> aw"


section \<open>Propositions\<close>

consts
    conform             :: \<sigma>
    corrective_action   :: \<sigma>


section \<open>Normative statements\<close>

text \<open>
    Primary obligation:
    the high-risk AI system ought to conform to the requirements.
\<close>

abbreviation A20_primary :: \<sigma> where
    "A20_primary \<equiv> \<circle><conform|\<^bold>\<top>>"


text \<open>
    Contrary-to-duty obligation:
    given non-conformity, corrective action ought to be taken.
\<close>

abbreviation A20_corrective :: \<sigma> where
    "A20_corrective \<equiv>
        \<circle><corrective_action|\<^bold>\<not>conform>"

text \<open>
    Concrete case:
    the system is not conforming in the actual world.
\<close>

abbreviation A20_nonconformity :: \<sigma> where
    "A20_nonconformity \<equiv> \<^bold>\<not>conform"


section \<open>Article20 theory\<close>

axiomatization where
    article20_primary:
        "\<lfloor>A20_primary\<rfloor>"
and
    article20_corrective:
        "\<lfloor>A20_corrective\<rfloor>"
and
    article20_case:
        "\<lfloor>A20_nonconformity\<rfloor>\<^sub>l"


section \<open>ModalLens query\<close>

text \<open>
    We investigate whether the conditional contrary-to-duty obligation,
    together with actual non-conformity, entails an unconditional
    obligation to take corrective action.

    Countermodels therefore expose the difference between global 
    optimality and optimality relative to the non-conformity context.
\<close>

abbreviation modal_lens_query :: bool where
    "modal_lens_query \<equiv>
        \<lfloor>\<^bold>\<circle><corrective_action>\<rfloor>\<^sub>l"

end
