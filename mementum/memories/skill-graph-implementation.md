# Skill Graph Implementation

## What
Implemented skill graph data structures and basic operations for OV5.

## Module
`lisp/modules/gptel-auto-workflow-skill-graph.el`

## Data Structures

### `ov5-sg-node` — Skill node
- `id`: symbol (e.g., `'hashline-edit`)
- `level`: `atom` | `molecule` | `compound`
- `path`: path to SKILL.md
- `metadata`: alist from YAML frontmatter
- `stats`: plist with `:usage-count`, `:success-rate`, `:last-used`

### `ov5-sg-edge` — Skill co-occurrence edge
- `from`, `to`: node ids
- `weight`: float 0.0–1.0
- `type`: `sequence` | `co-occurrence` | `dependency`
- `stats`: `:success-count`, `:total-count`, `:last-used`

## Functions

### Loading
- `ov5-sg-load-all-skills` — Load all skills from `assistant/skills/`
- `ov5-sg--load-skill` — Load single skill from directory
- `ov5-sg--parse-frontmatter` — Parse YAML frontmatter

### Traversal
- `ov5-sg-neighbors` — Get neighbors of a node
- `ov5-sg--edge-weight` — Get weight of edge

### Updates
- `ov5-sg--update-edge` — Reinforce +0.05 on success, decay *0.99 on failure
- `ov5-sg--record-experiment-skills` — Record skill usage from AutoTTS traces

### Design-Time
- `ov5-sg--compile-molecule` — STUB for molecule compilation

## Test Results
6/6 tests pass:
- `skill-graph-load-skills` — Loads 26 skills
- `skill-graph-node-levels` — Correctly parses atom/molecule/compound
- `skill-graph-edge-update` — Weight reinforcement and decay
- `skill-graph-record-experiment` — Creates edges from experiment
- `skill-graph-neighbors` — Neighbor lookup
- `skill-graph-empty-graph` — Graceful empty graph handling

## Integration
- Ontology router now uses real skill graph data for `graph-neighbor-success`
- `graph-edge-strength` looks up edges between active skills

## Next Steps
1. Implement molecule compilation with PPR or beam search
2. Add skill graph evolution trigger to hourly cron
3. Auto-discover edges from experiment history (not just real-time)
4. Persist graph to JSON
5. Add `atoms:` and `molecules:` frontmatter fields to skills

## Related
- `mementum/memories/skill-graph-three-layer-taxonomy.md`
- `mementum/memories/ov5-skill-graph-self-evolution.md`
- `mementum/memories/skill-level-frontmatter.md`
