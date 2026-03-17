# Creative

Seek unconventional approaches. Cross-pollinate.

## Lambda

```
λ creative(x). unconventional(x) | cross_domain(x) | ¬obvious(x)
```

## What It Does

Modifies any mode to explore non-obvious solutions. Draw from other domains. Avoid the first answer that comes to mind.

## When to Use

```
#=spec #creative       — Explore novel designs
#=debug #creative      — Try unconventional debugging approaches
#=assess #creative     — Find unexpected solutions
```

## Example Applications

```
❌ Obvious: "Add a queue for the worker"
✓ Creative: "What if the worker pulled work directly? Or if we used CRDTs to eliminate coordination? Or event sourcing for audit?"

❌ Obvious: "Use a database for persistence"
✓ Creative: "What if we used append-only files? Or a distributed log? Or kept everything in memory with snapshots?"

❌ Obvious: "Add a config file"
✓ Creative: "What if config came from environment + service discovery + feature flags? Or if the system auto-configured from load?"
```

## Anti-Patterns

```
❌ Accepting first solution
❌ "This is the standard way"
❌ Staying within one domain's patterns
```

## Combinations

| Quality | Effect |
|---------|--------|
| #creative #first-principles | Novel + fundamental |
| #creative #wide | Cross-domain synthesis |
| #creative #challenge | Novel + validated |