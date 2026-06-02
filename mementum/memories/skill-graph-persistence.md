# Skill Graph Persistence

## What
Implemented save/load for skill graph using Lisp-readable format.

## Why JSON Failed
`json-encode` doesn't handle plists correctly — serializes them as arrays:
```json
{"level":["atom","path","/tmp/a.md","stats",{"success-rate":0.8}]}
```

## Solution: `.eld` Format
Uses `prin1`/`read` for reliable roundtrip:
```elisp
(ov5-sg--restore
  ((a atom "/tmp/a.md" (:success-rate 0.9))
   (b atom "/tmp/b.md" (:success-rate 0.8)))
  ((a b 0.5 sequence (:success-count 1 :total-count 1)))
  nil)
```

## Functions
- `ov5-sg-save` — Write to `var/tmp/skill-graph.eld`
- `ov5-sg-load` — Read from `var/tmp/skill-graph.eld`
- `ov5-sg--serialize` — Convert graph to restore expression
- `ov5-sg--restore` — Apply restore expression to graph

## Test Results
1/1 pass: roundtrip save/load preserves nodes, edges, molecules

## Files Changed
- `lisp/modules/gptel-auto-workflow-skill-graph.el`

## Next Steps
1. Auto-save after each experiment
2. Auto-load on daemon startup
3. Backup old versions before overwrite
4. Compress large graphs (gzip)

## Related
- `mementum/memories/skill-graph-implementation.md`
- `mementum/memories/molecule-compilation.md`
