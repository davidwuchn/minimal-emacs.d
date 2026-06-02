# Atoms/Molecules Frontmatter

## What
Added `atoms:` and `molecules:` fields to skill frontmatter, enabling explicit dependency relationships.

## Schema

### Atoms field (for molecule-level skills)
```yaml
atoms: [elisp-discover, elisp-expert, elisp-validator]
```
Lists atom skills that this molecule composes.

### Molecules field (for compound-level skills)
```yaml
molecules: [benchmark-improver, evolution-patterns, skill-eval]
```
Lists molecule skills that this compound orchestrates.

## Skills Updated

### Molecules with `atoms:` (11 skills)
- `elisp-refactor` → [elisp-discover, elisp-expert, elisp-validator]
- `elisp-discover` → [elisp-expert]
- `benchmark-improver` → [eight-keys-grader, elisp-expert, evolution-patterns]
- `eight-keys-grader` → [elisp-validator]
- `evolution-patterns` → [provider-error-analyzer]
- `meta-harness-proposer` → [benchmark-improver, strategy-proposer]
- `sandbox-profiles` → [tool-prompts, agent-prompts]
- `strategy-proposer` → [elisp-expert]
- `research-digest` → [researcher-prompt]
- `researcher-prompt` → [agent-prompts]
- `skill-eval` → [elisp-expert, elisp-validator]

### Compounds with `molecules:` (2 skills)
- `auto-workflow` → [benchmark-improver, evolution-patterns, skill-eval, sandbox-profiles]
- `ov5` → [auto-workflow]

## Integration

On load, `ov5-sg--load-skill`:
1. Creates `dependency` edges from each atom → molecule
2. Creates `dependency` edges from each molecule → compound
3. Auto-registers molecules with `atoms:` in `ov5-sg--molecules`

## Parser Extension

`ov5-sg--parse-frontmatter` now handles:
- Simple values: `key: value`
- List values: `key: [val1, val2, val3]`
- Both return as alist entries

## Test Results
13/13 pass including `skill-graph-load-relations` and `skill-graph-molecules-registered`
