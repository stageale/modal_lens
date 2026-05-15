# Mathematical Formulation of Frame Statistics and Axiom Scoring

This document describes the mathematical basis of the modules:

```text
Src.Core.FrameStats
Src.Core.AxiomScoring
```

We consider a finite Kripke-style frame:

$$
F = (W, R)
$$

where:

$$
W = \{w_1, \dots, w_n\}
$$

is a finite set of worlds, and:

$$
R \subseteq W \times W
$$

is a binary accessibility relation.

An edge:

$$
(w,v) \in R
$$

means that world `v` is accessible from world `w`.

The number of worlds is:

$$
n = |W|
$$

For a world `w`, its successor set is:

$$
R(w) = \{v \in W \mid (w,v) \in R\}
$$

The outdegree of `w` is:

$$
d(w) = |R(w)|
$$

---

# 1. Frame Statistics

The module `FrameStats` computes structural quantities of the frame.

These quantities are used as support values for later axiom scoring.

For each axiom `A`, we compute:

$$
V_A
$$

as the number of violations of `A`, and:

$$
S_A
$$

as the support of `A`.

The support is the number of relevant active axiom instances in the concrete frame.

---

## 1.1 World Count

The world count is:

$$
|W| = n
$$

This is used as support for axioms that quantify over single worlds, such as seriality and reflexivity.

---

## 1.2 Edge Count

The edge count is:

$$
|R|
$$

This is the total number of accessibility edges.

---

## 1.3 Non-Loop Edge Count

The non-loop edge count is:

$$
|R_{\neq}| = |\{(w,v) \in R \mid w \neq v\}|
$$

This is used as support for symmetry.

The symmetry axiom is:

$$
\forall w \forall v \, ((w,v) \in R \rightarrow (v,w) \in R)
$$

Loops are trivially symmetric with themselves. Therefore, only non-loop edges are counted as active support.

---

## 1.4 Length-2 Path Count

The transitivity axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (u,v) \in R) \rightarrow (w,v) \in R)
$$

The active support for transitivity is the number of length-2 paths:

$$
P_2 = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (u,v) \in R\}|
$$

Equivalently:

$$
P_2 = \sum_{(w,u) \in R} d(u)
$$

This is implemented as:

```text
stats.length_2_path_count
```

---

## 1.5 Successor Pair Count

The Euclidean axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (w,v) \in R) \rightarrow (u,v) \in R)
$$

The active support is the number of ordered successor pairs:

$$
S = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (w,v) \in R\}|
$$

Equivalently:

$$
S = \sum_{w \in W} d(w)^2
$$

This includes the case:

$$
u = v
$$

This is implemented as:

```text
stats.successor_pair_count
```

---

## 1.6 Distinct Successor Pair Count

Sometimes we exclude trivial successor pairs where:

$$
u = v
$$

Then we count only distinct ordered successor pairs:

$$
S_{\neq} = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (w,v) \in R \wedge u \neq v\}|
$$

Equivalently:

$$
S_{\neq} = \sum_{w \in W} d(w)(d(w)-1)
$$

This is implemented as:

```text
stats.successor_distinct_pair_count
```

This support is used when:

```text
euclidean_mode: :distinct_pairs
```

---

# 2. Functionality Statistics

The functionality axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (w,v) \in R) \rightarrow u = v)
$$

Equivalently, every world has at most one successor:

$$
\forall w \, d(w) \leq 1
$$

There are three possible measurement modes.

---

## 2.1 Pair-Based Functionality

The pair-based support is the number of all ordered successor pairs:

$$
S_{fun}^{pairs} = \sum_{w \in W} d(w)^2
$$

The pair-based violation count is the number of ordered successor pairs with distinct successors:

$$
V_{fun}^{pairs} = \sum_{w \in W} d(w)(d(w)-1)
$$

The density is:

$$
D_{fun}^{pairs} = \frac{V_{fun}^{pairs}}{S_{fun}^{pairs}}
$$

This mode is used when:

```text
functional_mode: :pairs
```

This is the most direct interpretation of the axiom:

$$
((w,u) \in R \wedge (w,v) \in R) \rightarrow u = v
$$

---

## 2.2 Excess-Based Functionality

The excess-based measure counts how many successors are excessive.

For a single world:

$$
excess(w) = \max(d(w)-1,0)
$$

For the whole frame:

$$
V_{fun}^{excess} = \sum_{w \in W} \max(d(w)-1,0)
$$

The support is:

$$
S_{fun}^{excess} = n(n-1)
$$

The density is:

$$
D_{fun}^{excess} = \frac{V_{fun}^{excess}}{S_{fun}^{excess}}
$$

This mode is used when:

```text
functional_mode: :excess
```

This mode is softer than pair-based functionality.

---

## 2.3 Analysis-World-Based Functionality

If `FrameAnalysis` stores only the worlds that violate functionality, then we use:

$$
V_{fun}^{worlds} = |\{w \in W \mid d(w) > 1\}|
$$

The support is:

$$
S_{fun}^{worlds} = n
$$

The density is:

$$
D_{fun}^{worlds} = \frac{V_{fun}^{worlds}}{S_{fun}^{worlds}}
$$

This mode is used when:

```text
functional_mode: :analysis_worlds
```

---

# 3. Violation Density

For each axiom `A`, let:

$$
V_A
$$

be the number of violations, and:

$$
S_A
$$

be the active support.

If:

$$
S_A > 0
$$

then the violation density is:

$$
D_A = \frac{V_A}{S_A}
$$

If:

$$
S_A = 0
$$

then we define:

$$
D_A = 0
$$

This avoids division by zero.

---

# 4. Seriality

The seriality axiom is:

$$
\forall w \, \exists v \, ((w,v) \in R)
$$

A violation is a dead-end world:

$$
V_{serial} = |\{w \in W \mid R(w) = \emptyset\}|
$$

The support is:

$$
S_{serial} = n
$$

The density is:

$$
D_{serial} = \frac{V_{serial}}{S_{serial}}
$$

Since:

$$
S_{serial} = n
$$

we get:

$$
D_{serial} = \frac{V_{serial}}{n}
$$

In the implementation:

```text
V_serial = length(analysis.dead_ends)
S_serial = stats.world_count
```

---

# 5. Reflexivity

The reflexivity axiom is:

$$
\forall w \, ((w,w) \in R)
$$

A violation is a missing loop:

$$
V_{reflexive} = |\{w \in W \mid (w,w) \notin R\}|
$$

The support is:

$$
S_{reflexive} = n
$$

The density is:

$$
D_{reflexive} = \frac{V_{reflexive}}{S_{reflexive}}
$$

Since:

$$
S_{reflexive} = n
$$

we get:

$$
D_{reflexive} = \frac{V_{reflexive}}{n}
$$

In the implementation:

```text
V_reflexive = length(analysis.missing_loops)
S_reflexive = stats.world_count
```

---

# 6. Symmetry

The symmetry axiom is:

$$
\forall w \forall v \, ((w,v) \in R \rightarrow (v,w) \in R)
$$

A violation is an edge without its reverse edge:

$$
V_{symmetric} = |\{(w,v) \in R \mid w \neq v \wedge (v,w) \notin R\}|
$$

The support is the number of non-loop edges:

$$
S_{symmetric} = |\{(w,v) \in R \mid w \neq v\}|
$$

The density is:

$$
D_{symmetric} = \frac{V_{symmetric}}{S_{symmetric}}
$$

In the implementation:

```text
V_symmetric = length(analysis.antisymmetries)
S_symmetric = stats.non_loop_edge_count
```

---

# 7. Transitivity

The transitivity axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (u,v) \in R) \rightarrow (w,v) \in R)
$$

A violation is a length-2 path without a shortcut:

$$
V_{transitive} = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (u,v) \in R \wedge (w,v) \notin R\}|
$$

The support is the number of length-2 paths:

$$
S_{transitive} = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (u,v) \in R\}|
$$

Equivalently:

$$
S_{transitive} = \sum_{(w,u) \in R} d(u)
$$

The density is:

$$
D_{transitive} = \frac{V_{transitive}}{S_{transitive}}
$$

In the implementation:

```text
V_transitive = length(analysis.missing_hulls)
S_transitive = stats.length_2_path_count
```

---

# 8. Euclideanness

The Euclidean axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (w,v) \in R) \rightarrow (u,v) \in R)
$$

A violation is a pair of successors where the required edge is missing:

$$
V_{euclidean} = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (w,v) \in R \wedge (u,v) \notin R\}|
$$

There are two support modes.

---

## 8.1 All-Pairs Euclidean Support

The all-pairs support is:

$$
S_{euclidean}^{all} = \sum_{w \in W} d(w)^2
$$

The density is:

$$
D_{euclidean}^{all} = \frac{V_{euclidean}}{S_{euclidean}^{all}}
$$

This is used when:

```text
euclidean_mode: :all_pairs
```

---

## 8.2 Distinct-Pairs Euclidean Support

The distinct-pairs support is:

$$
S_{euclidean}^{distinct} = \sum_{w \in W} d(w)(d(w)-1)
$$

The density is:

$$
D_{euclidean}^{distinct} = \frac{V_{euclidean}}{S_{euclidean}^{distinct}}
$$

This is used when:

```text
euclidean_mode: :distinct_pairs
```

In the implementation:

```text
V_euclidean = length(analysis.missing_spans)
```

If:

```text
euclidean_mode: :all_pairs
```

then:

```text
S_euclidean = stats.successor_pair_count
```

If:

```text
euclidean_mode: :distinct_pairs
```

then:

```text
S_euclidean = stats.successor_distinct_pair_count
```

---

# 9. Functionality

The functionality axiom is:

$$
\forall w \forall u \forall v \, (((w,u) \in R \wedge (w,v) \in R) \rightarrow u = v)
$$

Equivalently:

$$
\forall w \, d(w) \leq 1
$$

There are three support modes.

---

## 9.1 Pair-Based Functionality

The support is:

$$
S_{functional}^{pairs} = \sum_{w \in W} d(w)^2
$$

The violation count is:

$$
V_{functional}^{pairs} = \sum_{w \in W} d(w)(d(w)-1)
$$

The density is:

$$
D_{functional}^{pairs} = \frac{V_{functional}^{pairs}}{S_{functional}^{pairs}}
$$

In the implementation:

```text
V_functional = stats.functional_pair_violations
S_functional = stats.functional_pair_support
```

---

## 9.2 Excess-Based Functionality

The violation count is:

$$
V_{functional}^{excess} = \sum_{w \in W} \max(d(w)-1,0)
$$

The support is:

$$
S_{functional}^{excess} = n(n-1)
$$

The density is:

$$
D_{functional}^{excess} = \frac{V_{functional}^{excess}}{S_{functional}^{excess}}
$$

In the implementation:

```text
V_functional = stats.functional_excess
S_functional = stats.functional_excess_support
```

---

## 9.3 Analysis-World-Based Functionality

The violation count is:

$$
V_{functional}^{worlds} = |analysis.function\_violations|
$$

The support is:

$$
S_{functional}^{worlds} = n
$$

The density is:

$$
D_{functional}^{worlds} = \frac{V_{functional}^{worlds}}{S_{functional}^{worlds}}
$$

In the implementation:

```text
V_functional = MapSet.size(analysis.function_violations)
S_functional = stats.world_count
```

---

# 10. Weighted Axiom Scoring

Each axiom `A` receives a heuristic weight:

$$
\omega_A > 0
$$

The support boost is:

$$
B_A = \log(1 + S_A)
$$

The final score is:

$$
Score_A = \omega_A \cdot D_A \cdot B_A
$$

Expanded:

$$
Score_A = \omega_A \cdot \frac{V_A}{S_A} \cdot \log(1 + S_A)
$$

for:

$$
S_A > 0
$$

If:

$$
S_A = 0
$$

then:

$$
D_A = 0
$$

and therefore:

$$
Score_A = 0
$$

---

# 11. Default Weights

The default weights are:

$$
\omega_{serial} = 1.0
$$

$$
\omega_{reflexive} = 1.0
$$

$$
\omega_{symmetric} = 1.0
$$

$$
\omega_{transitive} = 1.4
$$

$$
\omega_{euclidean} = 1.3
$$

$$
\omega_{functional} = 1.2
$$

These weights are heuristic and may be adjusted.

---

# 12. Interpretation

The score combines three quantities:

$$
D_A
$$

the violation density,

$$
B_A
$$

the logarithmic support boost, and:

$$
\omega_A
$$

the heuristic weight.

A high score means that the axiom has many violations relative to its active support, that the support is sufficiently large, and that the axiom has a high heuristic priority.

A high score does not automatically mean that the axiom should be added. It means that the axiom is structurally relevant as a refinement candidate.

---

# 13. Conceptual Pipeline

The pipeline is:

```text
FrameAnalysis
  -> provides concrete violations

FrameStats
  -> computes active support values

AxiomScoring
  -> computes density, support boost, weight, and score

Ranking
  -> sorts axioms by descending score
```

For each axiom `A`, the system computes:

$$
(V_A, S_A, D_A, B_A, \omega_A, Score_A)
$$

where:

$$
D_A = \frac{V_A}{S_A}
$$

if:

$$
S_A > 0
$$

and:

$$
D_A = 0
$$

if:

$$
S_A = 0
$$

The support boost is:

$$
B_A = \log(1 + S_A)
$$

The final ranking score is:

$$
Score_A = \omega_A \cdot D_A \cdot B_A
$$

---

# 14. Relation to Asymptotic Normalisation

A simpler normalization would divide by a worst-case polynomial search space.

For seriality and reflexivity:

$$
\frac{V_A}{n}
$$

For symmetry:

$$
\frac{V_A}{n^2}
$$

For transitivity, euclideanness, and functionality:

$$
\frac{V_A}{n^3}
$$

The density-based approach is more precise.

Instead of normalizing by the worst-case space:

$$
n^k
$$

it normalizes by the active support in the concrete frame:

$$
S_A
$$

For transitivity, this means using the actual number of length-2 paths:

$$
S_{transitive} = |\{(w,u,v) \in W^3 \mid (w,u) \in R \wedge (u,v) \in R\}|
$$

instead of:

$$
n^3
$$

Thus, the scoring is sensitive to the actual structure of the countermodel.

---

# 15. Summary Table

| Axiom | Violation Count | Support |
|---|---:|---:|
| Seriality | dead-end worlds | world count |
| Reflexivity | missing loops | world count |
| Symmetry | edges without reverse edge | non-loop edges |
| Transitivity | length-2 paths without shortcut | length-2 paths |
| Euclideanness | successor pairs without required edge | successor pairs |
| Functionality, pairs | distinct successor pairs | all successor pairs |
| Functionality, excess | excess successors | n(n-1) |
| Functionality, worlds | violating worlds | world count |

---

# 16. Final Formula

For every axiom `A`:

$$
V_A = \text{number of violations}
$$

$$
S_A = \text{active support}
$$

$$
D_A = \text{violation density}
$$

$$
B_A = \text{support boost}
$$

$$
\omega_A = \text{heuristic weight}
$$

If:

$$
S_A > 0
$$

then:

$$
D_A = \frac{V_A}{S_A}
$$

If:

$$
S_A = 0
$$

then:

$$
D_A = 0
$$

The support boost is:

$$
B_A = \log(1 + S_A)
$$

The final score is:

$$
Score_A = \omega_A \cdot D_A \cdot B_A
$$

Axioms are ranked by descending value of:

$$
Score_A
$$