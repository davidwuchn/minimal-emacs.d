# Molecule Compilation

## What
Implemented greedy molecule compilation in skill graph.

## Algorithm

```elisp
ov5-sg--compile-molecule(goal, max-atoms=10):
  1. Find best starting atom:
     - Among all atoms, compute score = success-rate + keyword-match-boost
     - keyword-match-boost = 0.3 if atom name appears in goal
     - Select atom with highest score
  
  2. Greedily extend path:
     - From current atom, find all unvisited atom neighbors
     - Select neighbor with highest edge weight
     - Add to path if weight > 0.1
     - Mark visited
  
  3. Stop when:
     - Path length = max-atoms
     - No unvisited neighbor with weight > 0.1
  
  4. Return path in forward order
```

## Properties
- **Deterministic**: Same graph + goal → same molecule
- **Bounded**: Never exceeds max-atoms (default: 10)
- **Greedy**: Local optimum, not global
- **Level-aware**: Only follows atom→atom edges

## Test Results
4/4 pass:
- `skill-graph-compile-molecule-empty` — Returns nil for empty graph
- `skill-graph-compile-molecule-single` — Returns single best atom
- `skill-graph-compile-molecule-chain` — Follows strong edges
- `skill-graph-compile-molecule-max-atoms` — Respects length limit

## Files Changed
- `lisp/modules/gptel-auto-workflow-skill-graph.el`

## Next Steps
1. Add `atoms:` and `molecules:` frontmatter to skills for explicit definition
2. Implement beam search for better global optimization
3. Add molecule caching (compile once, reuse)
4. Persist compiled molecules to JSON

## Related
- `mementum/memories/skill-graph-implementation.md`
- `mementum/memories/skill-level-frontmatter.md`
