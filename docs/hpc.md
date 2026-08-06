# HPC execution

## Status

HPC execution is an experimental adapter path. The local Isabelle execution path remains the primary development and review configuration.

The architectural requirement is:

> Remote execution must preserve the same enumeration, artifact, and validation contracts as local execution.

It must not become a second application pipeline.

## Current boundary

`Src.Isabelle.HPCConnect` adapts generated Isabelle inputs to the external `HpcConnect` dependency.

Before remote execution, the adapter expects valid generated inputs such as:

```text
ROOT
TheoryName.thy
```

Input validation occurs before backend availability checks. Tests should therefore create valid Isabelle files before asserting missing-backend behaviour.

## Runtime configuration

The current runtime configuration reads values such as:

```text
HPC_CONNECT_CLUSTER
HPC_CONNECT_USERNAME
HPC_CONNECT_KEY_PATH
HPC_CONNECT_ENV_FILE
HPC_CONNECT_SSH_ALIAS
HPC_CONNECT_PROXY_JUMP
HPC_CONNECT_WORK_DIR
HPC_CONNECT_VAULT_DIR
AXIOM_REFINER_HPC_REMOTE_BASE_DIR
AXIOM_REFINER_HPC_ISABELLE_BIN
AXIOM_REFINER_HPC_PREAMBLE
```

During the ModalLens rename, project-specific variables should become:

```text
MODALLENS_HPC_REMOTE_BASE_DIR
MODALLENS_HPC_ISABELLE_BIN
MODALLENS_HPC_PREAMBLE
```

Generic `HPC_CONNECT_*` variables belong to the dependency and should remain unchanged.

## Intended workload split

The current design discussion considers:

- Isabelle and Elixir orchestration on AION;
- Python graph analysis and verbalisation on IRIS.

This split is a deployment plan, not yet a validated performance result. It should be confirmed through measurement rather than encoded as a permanent architectural assumption.

## Reproducibility requirements

A remote run should record:

- cluster and partition;
- job identifier;
- node and accelerator type;
- requested CPUs, memory, and time;
- loaded modules or container image;
- source revision;
- dependency lock files;
- remote working directory;
- exact Isabelle executable;
- Python environment and model revision;
- stdout, stderr, exit status, and runtime.

## Benchmark dimensions

Before treating HPC as the primary path, benchmark:

- Isabelle startup and per-iteration time;
- model count and search-theory generation overhead;
- graph feature extraction time by model count and cardinality;
- clustering and pattern-mining time;
- verbalisation latency and memory;
- transfer and queue overhead;
- total time-to-result;
- output equivalence with local execution.

## Failure policy

Remote failures should return structured errors to `Execution.Pipeline` and persist the run manifest. Partial remote artifacts should either be downloaded and registered or explicitly marked unavailable.

Silent fallback from HPC to local execution is undesirable for experiments because it obscures provenance.
