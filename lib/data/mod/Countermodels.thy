theory AXIOM_REFINER_SEARCH
    imports AXIOM_REFINER_INPUT
begin

(* AXIOM_REFINER_BLOCKS *)

lemma axiom_refiner_probe:
    "axiom_refiner_query"
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