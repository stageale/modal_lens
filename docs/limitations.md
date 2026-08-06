# Limitations

## Interpretation limits

### Finite search

ModalLens analyses finite structures found within the configured Isabelle/Nitpick scope. Failure to find a model is not automatically:

- a proof of inconsistency;
- a proof of validity;
- a completeness result.

Any such claim requires a separate logical argument.

### Enumeration completeness

Blocking axioms exclude the finite structures represented by the parser and selected blocking options. Enumeration completeness depends on:

- the selected scope;
- parser fidelity;
- whether valuations are included;
- whether the designated world is included;
- logic-specific model identity;
- Nitpick search behaviour.

### Cluster meaning

Clusters depend on the selected feature representation and clustering algorithm. They are exploratory summaries, not semantic equivalence classes unless separately proved.

The current combined feature representation includes raw structural, Weisfeiler–Lehman, and graphlet features. Different features can produce different clusters.

### Pattern meaning

A characteristic pattern is a graphlet with support and contrast in the current sample. It is not:

- an axiom;
- a proof obligation;
- a sufficient explanation of a normative gap;
- guaranteed to generalise beyond the enumerated structures.

### Highlights

Highlights project pattern evidence onto worlds and edges. They show where recorded structural evidence occurs; they do not independently establish causation or logical necessity.

### Verbalisation

The language-model stage is optional and non-authoritative. Although input facts and output structure are constrained, generated wording can:

- omit relevant nuance;
- overstate a pattern;
- vary between environments;
- require manual correction.

The report and model artifacts remain authoritative.

## Implementation status

### Supported logics

The current parser and model layer target SDL and DDL representations. Additional modal or higher-order logics require explicit extensions to model, parser, export, and blocking-axiom semantics.

### Candidate refinement

Automatic candidate-axiom synthesis and iterative human selection are not yet part of the validated pipeline.

The current endpoint is:

```text
enumerated models
→ clusters and patterns
→ highlighted and verbalised evidence
```

A future refinement stage should be a separate, versioned component.

### User interface

The HTML interface is a prototype review surface, not a hardened multi-user web application. It writes a static page and local assets.

### HPC execution

The local execution path is primary. The HPC adapter is experimental and has not yet been benchmarked as the authoritative path for the full mixed workload.

### Resource requirements

Isabelle, graph analysis, and language-model inference have different resource profiles. Verbalisation with multi-billion-parameter models is not practical on every development laptop.

### Version metadata

The Elixir and Python package versions may currently differ. They should be unified before a public release.

### Public naming

The public name is transitioning from Axiom Refiner to ModalLens. Executable names, environment variables, application identifiers, schema prefixes, and internal namespaces must not be partially renamed in a release.

## Security and robustness

The prototype validates artifact paths against the run output directory and validates JSON envelopes at cross-language boundaries. It is not designed to safely execute untrusted Isabelle theories, arbitrary shell configuration, or untrusted model backends.

## Research claims not yet established

The current implementation does not by itself establish:

- that the selected feature method is optimal;
- that clusters correspond to human-recognisable normative categories;
- that verbalisation improves reviewer accuracy;
- that generated candidate refinements will be sound or useful;
- that HPC execution improves total time-to-result;
- that results generalise beyond the current examples.

These require explicit experiments and evaluation criteria.
