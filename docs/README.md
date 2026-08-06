# ModalLens documentation

This directory contains the reviewer-oriented documentation for **ModalLens: A Modal Semantics Explorer**.

## Recommended reading order

1. [`reviewer-guide.md`](reviewer-guide.md) — scope, contribution, and quickest reproducible path.
2. [`architecture.md`](architecture.md) — component responsibilities and control flow.
3. [`artifact-contracts.md`](artifact-contracts.md) — durable Elixir–Python exchange formats.
4. [`reproducibility.md`](reproducibility.md) — environment, tests, and experiment records.
5. [`limitations.md`](limitations.md) — boundaries of interpretation and implementation status.

## Reference documentation

- [`cli.md`](cli.md) — commands, modes, and option semantics.
- [`verbalization.md`](verbalization.md) — deterministic facts, prompts, backends, and result validation.
- [`hpc.md`](hpc.md) — experimental remote-execution boundary.
- [`documentation-migration.md`](documentation-migration.md) — rename and documentation cleanup plan.

## Documentation policy

The codebase should use:

- module-level documentation for component responsibility;
- documentation and types for public functions;
- inline comments only where the reason for an implementation decision is not evident from the code;
- versioned artifact documentation for all durable cross-language contracts.

Line-by-line comments are intentionally avoided. They obscure control flow and tend to become stale faster than the implementation.

## Naming status

The public name is **ModalLens**. Some current implementation identifiers may still use the former project name until the mechanical rename is complete. The migration plan identifies which names must be changed atomically and which internal namespaces may remain temporarily.
