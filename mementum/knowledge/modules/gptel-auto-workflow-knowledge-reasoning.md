# auto workflow knowledge reasoning

## Purpose

Formal reasoning engine for the OV5 knowledge layer. Provides Horn SAT
consistency checking for ontology integrity, Floyd-Warshall transitive closure
for causal chains across experiment sequences, Allen interval algebra (13
relations) for temporal gap detection, O(1) interval labelling for pattern
subsumption, 8 forward-chaining rules for experiment inference, OWL/SHACL
ontology generation from experiment results, deterministic EDN plist formatting
for prompt construction, and DIALECTIC.md moderator intervention for forced
backend swaps after consecutive failures.

## File Stats

- **Lines**: 646
- **Path**: `lisp/modules/gptel-auto-workflow-knowledge-reasoning.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-knowledge--horn-clause-p` | 17 | Validate Horn clause structure |
| `gptel-knowledge--horn-sat-p` | 28 | Linear-time Horn SAT via forward chaining |
| `gptel-knowledge--check-ontology-consistency` | 54 | Check ontology rules for logical contradictions |
| `gptel-knowledge--floyd-warshall` | 79 | Compute transitive closure and shortest causal paths |
| `gptel-knowledge--allen-classify` | 195 | Classify temporal relation between two intervals |
| `gptel-knowledge--allen-detect-gaps` | 202 | Detect temporal gaps in experiment intervals |
| `gptel-knowledge--build-interval-labels` | 239 | Build preorder/postorder labels for O(1) subsumption |
| `gptel-knowledge--subsumes-p` | 259 | O(1) check: does super-pattern subsume sub-pattern? |
| `gptel-knowledge--forward-chain` | 326 | Apply 8 forward-chaining rules to fixed point |
| `gptel-knowledge--generate-owl` | 356 | Generate OWL ontology as Turtle string |
| `gptel-knowledge--generate-shacl` | 391 | Generate SHACL shapes as Turtle string |
| `gptel-knowledge--plist-to-edn` | 453 | Convert plist to EDN format (deterministic, zero LLM) |
| `gptel-knowledge--forge-lambda-fixed-point` | 474 | Resolve prompt spec against context until fixed point |
| `gptel-knowledge--playout-cap-randomize` | 513 | 80/15/5 depth randomization (AutoGo-inspired) |
| `gptel-knowledge--dialectic-check` | 562 | Check for failures requiring moderator intervention |
| `gptel-knowledge--frontier-select-targets` | 585 | Pareto frontier target selection from TSV history |

## Dependencies

- `cl-lib`, `json`

## Integration Points

- **Ontology consistency**: Called before ontology routing to validate rules
- **Causal analysis**: Used by evolution cycle to find root causes of failures
- **Temporal analysis**: Detects gaps in experiment sequences for research phase
- **Forward chaining**: Drives experiment inference (saturated targets, frozen categories, etc.)
- **DIALECTIC.md moderator**: Triggers forced backend swaps after 3+ consecutive failures
- **EDN formatting**: Used by prompt-build for deterministic prompt construction
- **Target selection**: `frontier-select-targets` picks targets for the next experiment cycle

## See Also

- [auto workflow evolution](gptel-auto-workflow-evolution.md)
- [auto workflow ontology router](gptel-auto-workflow-ontology-router.md)
- [tools agent prompt build](gptel-tools-agent-prompt-build.md)
- [tools agent strategy harness](gptel-tools-agent-strategy-harness.md)