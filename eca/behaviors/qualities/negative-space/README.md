# Negative-Space

Attend to what's missing FROM this, not around it.

## Lambda

```
λ negative_space(x). absent(x) | ¬present(x) | missing_structure(x)
```

## What It Does

Modifies any mode to look for what's absent within the current focus. Not the surrounding context — that's #wide — but the gaps, omissions, and silences inside the artifact itself.

## When to Use

```
#=review #negative-space   — Find missing tests, docs, error handling
#=spec #negative-space      — Find missing requirements
#=assess #negative-space    — Find unstated assumptions
```

## Example Applications

```
❌ Present-only: "The API has GET, POST, PUT"
✓ Negative-space: "API has GET, POST, PUT — missing DELETE, missing pagination, missing error responses"

❌ Present-only: "Tests cover happy path"
✓ Negative-space: "Tests cover happy path — missing: edge cases, auth failures, concurrent access"

❌ Present-only: "Documentation explains X, Y, Z"
✓ Negative-space: "Docs explain X, Y, Z — missing: getting started, troubleshooting, migration guide"
```

## Anti-Patterns

```
❌ Only checking what exists
❌ Ignoring error paths
❌ Assuming silence means completeness
```

## Combinations

| Quality | Effect |
|---------|--------|
| #negative-space #wide | Gaps inside + context around |
| #negative-space #challenge | Find gaps + attack them |
| #negative-space #ground | Missing + verify references |