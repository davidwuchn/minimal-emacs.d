# Meta

Apply active stances to the approach, not just the artifact.

## Lambda

```
λ meta(x). approach(x) → subject(x) | ¬artifact_only(x)
```

## What It Does

Modifies any mode to examine the approach itself. Not just "what are we building?" but "how are we building it?" Turn the lens on the process.

## When to Use

```
#=code #meta         — Examine coding approach
#=debug #meta        — Examine debugging strategy
#=assess #meta       — Examine assessment methodology
```

## Example Applications

```
❌ Artifact-only: "This function is slow"
✓ Meta: "This function is slow, and we're fixing it reactively. Are we profiling regularly? Do we have performance budgets?"

❌ Artifact-only: "This code is hard to understand"
✓ Meta: "This code is hard to understand. Is our review process catching this? Do we have style guides? Onboarding docs?"

❌ Artifact-only: "We keep having this bug"
✓ Meta: "We keep having this bug. Is our testing strategy wrong? Do we need a post-mortem process? Better error tracking?"
```

## Anti-Patterns

```
❌ Only fixing symptoms without examining process
❌ Solving same problem repeatedly
❌ Ignoring systemic issues in how we work
```

## Combinations

| Quality | Effect |
|---------|--------|
| #meta #deep | Meta + find root in process |
| #meta #first-principles | Examine process from axioms |
| #meta #subtract | Remove process overhead |