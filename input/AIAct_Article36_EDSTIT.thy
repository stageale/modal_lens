theory AIAct_Article36_EDSTIT
  imports Epistemic_Deontic_STIT
begin


section \<open>Agents\<close>

consts
  notifying_authority :: ag
  notified_body       :: ag

axiomatization where
  active_agents:
    "\<forall>a. Agent a \<longleftrightarrow> (a = notifying_authority \<or> a = notified_body)"

axiomatization where
  distinct_agents:
    "notifying_authority \<noteq> notified_body"


section \<open>Propositions\<close>

consts
  meets_requirements :: sigma
  investigate        :: sigma


section \<open>Article 36 use case\<close>

text \<open>
  The use case represents the first stage of Article 36(4).

  If the notifying authority believes that the notified body does not
  meet the relevant requirements, the notifying authority ought to
  investigate the matter.

  The temporal aspect of "no longer meets the requirements" is
  deliberately abstracted away in the present atemporal semantics.
\<close>

axiomatization where
  article36_investigation:
    "\<lfloor>(believes notifying_authority (\<^bold>\<not> meets_requirements)) \<^bold>\<rightarrow> (ought notifying_authority investigate)\<rfloor>"

axiomatization where
  actual_authority_belief:
    "\<lfloor>believes notifying_authority (\<^bold>\<not> meets_requirements)\<rfloor>\<^sub>a"


section \<open>ModalLens query\<close>

text \<open>
  We test whether the investigation obligation is incorrectly
  transferred from the notifying authority to the notified body.
\<close>

abbreviation modal_lens_query :: bool where
  "modal_lens_query \<equiv> \<lfloor>ought notified_body investigate\<rfloor>\<^sub>a"


end