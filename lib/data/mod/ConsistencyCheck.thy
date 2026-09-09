theory MODAL_LENS_SEARCH
    imports MODAL_LENS_INPUT
begin

(* MODAL_LENS_BLOCKS *)

lemma modal_lens_probe:
    "True"
    nitpick [
        satisfy,
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