# Research Pipeline Contract

**Updated:** 2026-05-31

## Key Principles

1. **Mandatory research hash per experiment** — Every experiment row in `results.tsv` must include a non-none research hash. Missing research = pipeline defect, not a valid empty result.

2. **Fail fast on daemon loss** — If a researcher daemon disappears after being observed, stop waiting and fall back immediately. Don't wait for global timeout.

3. **Structured research output** — Prefer machine-parseable format with fields:
   - `source`, `technique`, `apply-to-us`, `verification`

4. **Observable self-evolution** — Changes should be traceable via:
   - `results.tsv` metadata
   - Research traces
   - Controller decisions

## Anti-pattern
Treating "missing research file" as a successful empty run rather than a defect.

## Implication
Research daemon orchestration needs resilience: watch for daemon heartbeat, timeout locally, and surface defects clearly rather than silently swallowing missing outputs.
