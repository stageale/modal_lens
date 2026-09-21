theory AIActArticle20_EDSTIT
    imports Epistemic_Deontic_STIT
begin


section \<open>Agents\<close>

consts
    provider :: ag

axiomatization where
    active_agents:
        "\<forall>a. Agent a \<longleftrightarrow> (a = provider)"


section \<open>Propositions\<close>

consts 
    conform             :: sigma
    corrective_action   :: sigma


section \<open>Article 20\<close>

text \<open>
    Article 20(1) is represented by an epistemic trigger:
    if the provider believes that the system is not conforming,
    the provider ought to take corrective action.

    The actual conformity state is deliberately left unconstrained.
    Hence, the provider's belief may be correct or incorrect.
\<close>

axiomatization where
    article20_corrective:
        "\<lfloor>
            believes provider (\<^bold>\<not> conform)
        \<rfloor>\<^sub>a"


section \<open>ModalLens query\<close>

text \<open>
    The query asks whether the triggered agentive obligation already
    implies that the provider actually sees to it that corrective
    action is taken.
\<close>

abbreviation modal_lens_query :: bool where
    "modal_lens_query" \<equiv>
        \<lfloor>stit provider corrective_action\<rfloor>\<^sub>a"

end