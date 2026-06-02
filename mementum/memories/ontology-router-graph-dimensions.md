# Ontology Router Graph Dimensions

## What
Extended `gptel-auto-workflow--ranked-subagent-backends` with two new scoring dimensions for skill graph integration.

## Dimensions Added

### Phase γ: Graph Neighbor Success (`gptel-auto-workflow--graph-neighbor-success`)
- **Input**: backend, target
- **Logic**: Look up target's neighbors in skill graph, check backend's keep-rate on those neighbors
- **Current**: STUB returning 0.0
- **Future**: When skill graph data exists, boost backends that succeeded on similar targets

### Phase δ: Graph Edge Strength (`gptel-auto-workflow--graph-edge-strength`)
- **Input**: backend, active-skills
- **Logic**: Look up edges between active skills in skill graph, check backend's success when those skill pairs were used
- **Current**: STUB returning 0.0
- **Future**: When skill graph data exists, boost backends that succeeded with specific skill combinations

## Integration

Scoring formula updated:
```elisp
(+ (* health keep-rate)
   pref-boost
   axis-boost
   cold-start-boost
   graph-neighbor-boost    ; NEW
   graph-edge-boost)       ; NEW
```

Audit trail includes:
- `:graph-neighbor` — neighbor success boost value
- `:graph-edge` — edge strength boost value

## Files Changed
- `lisp/modules/gptel-auto-workflow-ontology-router.el`

## Next Steps
1. Implement skill graph data structures (nodes, edges, weights)
2. Fill in `gptel-auto-workflow--graph-neighbor-success` with real graph traversal
3. Fill in `gptel-auto-workflow--graph-edge-strength` with real edge lookup
4. AutoTTS trace integration: log skill combinations used per experiment

## Related
- `mementum/memories/skill-graph-three-layer-taxonomy.md`
- `mementum/memories/ov5-skill-graph-self-evolution.md`
- `mementum/memories/skill-level-frontmatter.md`
