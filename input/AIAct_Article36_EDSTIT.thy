theory AIActArticle36_EDSTIT
    imports Epistemic_Deontic_STIT
begin


section \<open>Agents\<close>

consts
    notifying_authority :: ag
    notified_body       :: ag

axiomatization where
    active_agents:
        "\<forall>a.
            Agent a
            \<longleftrightarrow>
            (a = notifying_authority \<or> a = notified_body)"

and distinct_agents:
    "notifying_authority \<noteq> notified_body"


section \<open>Propositions\<close>

consts
    meets_requirements  :: sigma
    investigate         :: sigma


section \<open>Article31 and Article 36\<close>

text \<open>
    The notified body is required to satisfy the relevant meets_requirements
    of Article 31.

    We use this only to make the different normative roles of the two agents explicit.
\<close>

axiomatization where
    article31_requirements:
        "\<lfloor>
            ought notified_body meets_requirements
        \<rfloor>"

text \<open>
    We represent the first stage of Article 36(4).

    If the notifying authority believes that the notified body does
    not meet the requirements, the notifying authority ought to
    investigate the matter.

    The temporal component of "no longer meets" is deliberately
    abstracted away in this atemporal use case.
\<close>

axiomatization where  
    article36_investigation:
        "\<lfloor>
            (believes notifying_authority
                (\<^bold>\<not> meets_requirements))
            \<^bold>\<rightarrow>
            (ought notifying_authority investigate)
        \<rfloor>"

and actual_authority_belief:
    "\<lfloor>
        believes notifying_authority
            (\<^bold>\<not> meets_requirements)
    \<rfloor>\<^sub>a"


section \<open>ModalLens query\<close>

text \<open>
    The query tests whether the investigation obligation is transferred
    to the notified body merely because that body is the subject of the
    suspected non-compliance.
\<close>

abbreviation modal_lens_query :: bool where
    "modal_lens_query \<equiv>
        \<lfoor>ought notified_body investigate\<rfloor>\<^sub>a"

end