theory AIAct_Article36_EDSTIT
  imports Epistemic_Deontic_STIT
begin


section \<open>Agents\<close>

consts
  notifying_authority :: ag
  notified_body       :: ag

axiomatization where
  active_agents:
    "\<forall>a. Agent a \<longleftrightarrow>
      (a = notifying_authority \<or> a = notified_body)"

axiomatization where
  distinct_agents:
    "notifying_authority \<noteq> notified_body"


section \<open>Propositions\<close>

consts
  meets_requirements      :: sigma
  investigate             :: sigma
  designation_suspended   :: sigma
  inform_providers        :: sigma

text \<open>
  meets_requirements:
    The notified body meets the relevant requirements.

  investigate:
    The matter is investigated by the notifying authority.

  designation_suspended:
    The designation of the notified body is suspended.

  inform_providers:
    The providers concerned are informed by the notified body.
\<close>


section \<open>Norms from Article 36(4)--(5)\<close>

text \<open>
  Article 36(4) requires the notifying authority to investigate
  when it has sufficient reason to consider that the notified body
  no longer meets the relevant requirements.

  We abstract this assessment as a belief in non-compliance.
  Temporal aspects and procedural details are omitted.
\<close>

axiomatization where
  article36_investigation:
    "\<lfloor>
      (believes notifying_authority (\<^bold>\<not> meets_requirements))
      \<^bold>\<rightarrow>
      (ought notifying_authority investigate)
    \<rfloor>"

text \<open>
  Under Article 36(5), suspension of the designation triggers the
  notified body's duty to inform the providers concerned. The ten-day
  deadline is outside this atemporal abstraction.
\<close>

axiomatization where
  article36_inform_providers:
    "\<lfloor>
      designation_suspended
      \<^bold>\<rightarrow>
      (ought notified_body inform_providers)
    \<rfloor>"
    

section \<open>Case assumptions\<close>

axiomatization where
  actual_authority_belief:
    "\<lfloor>
      believes notifying_authority (\<^bold>\<not> meets_requirements)
    \<rfloor>\<^sub>a"

text \<open>
  In the actual case, the notifying authority has brought about the
  suspension of the designation. This is a separate case assumption;
  it is not inferred from the authority's belief or investigation duty.
\<close>

axiomatization where
  actual_authority_suspension:
    "\<lfloor>stit notifying_authority designation_suspended\<rfloor>\<^sub>a"


section \<open>ModalLens query\<close>

text \<open>
  By reflexivity of the notifying authority's STIT relation, the case
  assumption entails that the designation is suspended at the actual
  world. Article 36(5) therefore triggers the notified body's obligation
  to inform the providers concerned.

  We ask whether the notified body already sees to it that the providers
  are informed. Fulfilment of that obligation need not follow.
\<close>

abbreviation modal_lens_query :: bool where
  "modal_lens_query \<equiv>
    \<lfloor>stit notified_body inform_providers\<rfloor>\<^sub>a"

end