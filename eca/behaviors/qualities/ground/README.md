# Ground

Verify every term resolves. Compositions don't contradict.

## Lambda

```
λ ground(x). referent(x) → defined(x) | ¬ungrounded(x)
```

## What It Does

Modifies any mode to ensure every term has a concrete referent. No floating abstractions — everything must eventually resolve to something observable or measurable.

## When to Use

```
#=spec #ground      — Verify all terms are defined
#=assess #ground    — Check claims have evidence
#=review #ground    — Ensure code references exist
```

## Example Applications

```
❌ Ungrounded: "The system should be more robust"
✓ Grounded: "The system should handle 10x traffic without latency > 500ms"

❌ Ungrounded: "Improve performance"
✓ Grounded: "Reduce p99 latency from 2s to <500ms as measured by Prometheus"

❌ Ungrounded: "Better error handling"
✓ Grounded: "All API errors return structured JSON with code, message, and trace_id"
```

## Anti-Patterns

```
❌ Floating abstractions
❌ "Handle properly" without definition
❌ Unmeasurable claims
```

## Combinations

| Quality | Effect |
|---------|--------|
| #ground #deep | Deep + verified |
| #ground #first-principles | Ground in axioms |
| #ground #concise | Grounded + brief |