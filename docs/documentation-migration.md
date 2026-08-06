# Documentation and rename migration

## Goal

Prepare one coherent reviewer-facing documentation set under the public name:

```text
ModalLens: A Modal Semantics Explorer
```

The rename and documentation cleanup should happen in controlled commits so that functional changes remain reviewable.

## Existing documents

### Delete from active documentation

#### `docs/demo_gallery_tutorial.md`

**Action:** delete.

Reason:

- references removed modules such as `Src.VisualExplanations.DemoGallery`;
- describes the retired hardcoded axiom-explanation gallery;
- uses obsolete output paths and colour semantics;
- no longer represents the canonical pipeline.

Git history is sufficient archival storage.

#### `docs/scoring_math.md`

**Action:** delete from the reviewer branch.

Reason:

- documents the deprecated axiom-scoring pipeline;
- no active production command consumes the described scoring model;
- retaining it would imply that the current prototype still ranks or recommends axioms.

If its mathematical notes are useful for future research, preserve them outside active product documentation or recover them from version history.

#### `docs/LLM.md`

**Action:** delete and replace with [`verbalization.md`](verbalization.md).

Reason:

- incomplete;
- contains only an Ollama installation fragment;
- does not document deterministic facts, schemas, validation, seeds, or provenance.

#### `test/python/README.txt`

**Action:** delete.

Reason:

- contains temporary instructions to copy tests into another checkout;
- test commands belong in the root README and [`reproducibility.md`](reproducibility.md).

### Replace

#### `docs/enumeration_modes.md`

**Action:** replace with [`cli.md`](cli.md).

Reason:

- useful conceptual material, but stale module names and command semantics;
- refers to pre-refactor names such as `Src.ModelEnumeration`;
- documents positive `--auto-atoms` even though automatic detection is now the default;
- should be consolidated with the complete CLI reference.

### Keep and overwrite

#### Root `README.md`

Replace with the ModalLens reviewer draft after the executable and environment-variable rename is complete.

#### Dependency documentation

Files below `deps/` are third-party material. Do not edit or present them as ModalLens documentation. They should normally not be part of a source archive committed to the repository.

## Proposed documentation tree

```text
README.md
docs/
├── README.md
├── reviewer-guide.md
├── architecture.md
├── cli.md
├── artifact-contracts.md
├── verbalization.md
├── reproducibility.md
├── limitations.md
├── hpc.md
└── documentation-migration.md
```

After the migration is complete, `documentation-migration.md` may be removed from the public reviewer package or retained as an internal maintenance note.

## Mechanical project rename

Recommended public identifiers:

| Current | Target |
|---|---|
| Axiom Refiner | ModalLens |
| `axiom_refiner` | `modal_lens` |
| `axiom-refiner` | `modal-lens` |
| `AxiomRefiner` | `ModalLens` |
| `AXIOM_REFINER_*` | `MODALLENS_*` |
| `./axiom_refiner` | `./modal_lens` |

Potential schema migration:

| Current | Target |
|---|---|
| `axiom-refiner/model` | `modallens/model` |
| `axiom-refiner/analysis-report` | `modallens/analysis-report` |
| `axiom-refiner/graph-analysis-result` | `modallens/graph-analysis-result` |
| `axiom-refiner/verbalization-request` | `modallens/verbalization-request` |
| `axiom-refiner/verbalization-summary` | `modallens/verbalization-summary` |
| `axiom-refiner/verbalization-provenance` | `modallens/verbalization-provenance` |

Schema identifiers are contracts. Rename them in one commit together with:

- Elixir constants;
- Python constants;
- tests and fixtures;
- example artifacts;
- documentation.

Do not leave mixed prefixes in a release.

## Internal namespace decision

The internal `Src.*` namespace is visibly provisional. Two viable approaches exist:

1. **Conservative release preparation:** keep `Src.*` temporarily and rename only the public identity.
2. **Full namespace migration:** rename modules to `ModalLens.*` in one mechanical commit after all tests are green.

Do not rename individual subtrees gradually. Mixed internal namespaces make the architecture harder to review.

## Cleanup commands

After copying the replacement documentation:

```bash
rm -f \
  docs/demo_gallery_tutorial.md \
  docs/scoring_math.md \
  docs/LLM.md \
  docs/enumeration_modes.md \
  test/python/README.txt
```

Then verify stale references:

```bash
rg -n \
  "Axiom Refiner|axiom_refiner|axiom-refiner|AxiomRefiner|AXIOM_REFINER|Src\\.ModelEnumeration|DemoGallery|AxiomExplanation|axiom-scoring" \
  README.md docs lib graph_ml verbalization test cmd config mix.exs pyproject.toml
```

Review every remaining occurrence rather than applying a blind global replacement.

## Non-documentation repository cleanup

A public source archive should exclude generated or vendored runtime material such as:

```text
_build/
deps/
__pycache__/
.pytest_cache/
out/
generated search outputs
local model caches
```

These are build or runtime artifacts, not reviewer documentation.
