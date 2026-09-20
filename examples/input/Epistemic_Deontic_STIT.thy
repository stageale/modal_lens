theory Epistemic_Deontic_STIT
  imports Main
begin


section \<open>Types\<close>

typedecl i
typedecl ag

type_synonym sigma = "i \<Rightarrow> bool"


section \<open>Model structure\<close>

consts
  actual_world :: i
  Agent :: "ag \<Rightarrow> bool"

  RBox   :: "i \<Rightarrow> i \<Rightarrow> bool"
  RStit  :: "ag \<Rightarrow> i \<Rightarrow> i \<Rightarrow> bool"
  ROught :: "ag \<Rightarrow> i \<Rightarrow> i \<Rightarrow> bool"
  RBel   :: "ag \<Rightarrow> i \<Rightarrow> i \<Rightarrow> bool"


section \<open>Lifted propositional connectives\<close>

abbreviation mtrue :: sigma ("\<^bold>\<top>") where
  "\<^bold>\<top> \<equiv> \<lambda>w. True"

abbreviation mfalse :: sigma ("\<^bold>\<bottom>") where
  "\<^bold>\<bottom> \<equiv> \<lambda>w. False"

abbreviation mnot :: "sigma \<Rightarrow> sigma" ("\<^bold>\<not> _" [52] 53) where
  "\<^bold>\<not> \<phi> \<equiv> \<lambda>w. \<not> \<phi> w"

abbreviation mand :: "sigma \<Rightarrow> sigma \<Rightarrow> sigma"
  (infixr "\<^bold>\<and>" 51) where
  "\<phi> \<^bold>\<and> \<psi> \<equiv> \<lambda>w. \<phi> w \<and> \<psi> w"

abbreviation mor :: "sigma \<Rightarrow> sigma \<Rightarrow> sigma"
  (infixr "\<^bold>\<or>" 50) where
  "\<phi> \<^bold>\<or> \<psi> \<equiv> \<lambda>w. \<phi> w \<or> \<psi> w"

abbreviation mimp :: "sigma \<Rightarrow> sigma \<Rightarrow> sigma"
  (infixr "\<^bold>\<rightarrow>" 49) where
  "\<phi> \<^bold>\<rightarrow> \<psi> \<equiv>
     \<lambda>w. \<phi> w \<longrightarrow> \<psi> w"


section \<open>Modal operators\<close>

definition settled :: "sigma \<Rightarrow> sigma" where
  "settled \<phi> =
     (\<lambda>w. \<forall>v. RBox w v \<longrightarrow> \<phi> v)"

definition stit :: "ag \<Rightarrow> sigma \<Rightarrow> sigma" where
  "stit a \<phi> =
     (\<lambda>w. \<forall>v. RStit a w v \<longrightarrow> \<phi> v)"

definition ought :: "ag \<Rightarrow> sigma \<Rightarrow> sigma" where
  "ought a \<phi> =
     (\<lambda>w. \<forall>v. ROught a w v \<longrightarrow> \<phi> v)"

definition believes :: "ag \<Rightarrow> sigma \<Rightarrow> sigma" where
  "believes a \<phi> =
     (\<lambda>w. \<forall>v. RBel a w v \<longrightarrow> \<phi> v)"


section \<open>Validity\<close>

abbreviation valid :: "sigma \<Rightarrow> bool"
  ("\<lfloor>_\<rfloor>" [8] 109) where
  "\<lfloor>\<phi>\<rfloor> \<equiv> \<forall>w. \<phi> w"

abbreviation valid_actual :: "sigma \<Rightarrow> bool"
  ("\<lfloor>_\<rfloor>\<^sub>a" [8] 109) where
  "\<lfloor>\<phi>\<rfloor>\<^sub>a \<equiv> \<phi> actual_world"


section \<open>STIT and deontic frame conditions\<close>

axiomatization where

  RBox_refl:
    "\<forall>w. RBox w w"

and RBox_sym:
    "\<forall>w v.
       RBox w v \<longrightarrow> RBox v w"

and RBox_trans:
    "\<forall>w v u.
       RBox w v \<and> RBox v u
       \<longrightarrow> RBox w u"

and RStit_refl:
    "\<forall>a w.
       Agent a
       \<longrightarrow> RStit a w w"

and RStit_sym:
    "\<forall>a w v.
       Agent a \<and> RStit a w v
       \<longrightarrow> RStit a v w"

and RStit_trans:
    "\<forall>a w v u.
       Agent a \<and>
       RStit a w v \<and>
       RStit a v u
       \<longrightarrow> RStit a w u"

and RStit_moment:
    "\<forall>a w v.
       Agent a \<and> RStit a w v
       \<longrightarrow> RBox w v"

and independence_of_agents:
    "\<forall>w f.
       (\<forall>a.
          Agent a \<longrightarrow> RBox w (f a))
       \<longrightarrow>
       (\<exists>v.
          \<forall>a.
            Agent a \<longrightarrow> RStit a (f a) v)"

and ROught_moment:
    "\<forall>a w v.
       Agent a \<and> ROught a w v
       \<longrightarrow> RBox w v"

and ROught_can:
    "\<forall>a w.
       Agent a
       \<longrightarrow>
       (\<exists>v.
          RBox w v \<and>
          (\<forall>u.
             RStit a v u
             \<longrightarrow> ROught a w u))"

and ROught_settled:
    "\<forall>a w v u z.
       Agent a \<and>
       RBox w v \<and>
       RBox w u \<and>
       ROught a u z
       \<longrightarrow> ROught a v z"

and ROught_complete_choice:
    "\<forall>a w v.
       Agent a \<and>
       ROught a w v
       \<longrightarrow>
       (\<exists>u.
          RBox w u \<and>
          RStit a u v \<and>
          (\<forall>z.
             RStit a u z
             \<longrightarrow> ROught a w z))"


section \<open>Doxastic frame conditions\<close>

axiomatization where

  RBel_serial:
    "\<forall>a w.
       Agent a
       \<longrightarrow>
       (\<exists>v. RBel a w v)"

and RBel_trans:
    "\<forall>a w v u.
       Agent a \<and>
       RBel a w v \<and>
       RBel a v u
       \<longrightarrow> RBel a w u"

and RBel_euclidean:
    "\<forall>a w v u.
       Agent a \<and>
       RBel a w v \<and>
       RBel a w u
       \<longrightarrow> RBel a v u"


end