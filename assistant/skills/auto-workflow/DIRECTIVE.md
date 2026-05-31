---
name: auto-workflow-directive
description: OV5 consolidated — all intelligence lives in ontology, ai-behaviors, grader feedback, kept patterns, and concrete tasks
version: OV5.1
---

# OV5.1 Consolidated

All runtime intelligence is now provided by specialized OV5 systems.
This file is retained for legacy `load-skill-content` compatibility.

| System | What it provides | Injects into |
|--------|-----------------|--------------|
| Ontology | Category Focus/Avoid, action schemas, backend routing | `CATEGORY:` + `Action Schema` |
| ai-behaviors | Learned hashtags per (category × strategy × backend) | `BEHAVIOR:` in DIRECTIVE |
| Grader feedback | Per-criterion FAIL → concrete MUST instructions | `PREVIOUS GRADER FAILURES` |
| Kept patterns | Extracted code snippets from past successes | `PAST PATTERNS` |
| Concrete tasks | Deterministic task hints from target history | `TASK:` in DIRECTIVE |
| Byte-compile | Pre-grader compile check | Early validation |
| Staging review | Schema-aware safety check + accuracy feedback | Review prompt |
| Self-evolution | Learns strategies, weights, boundaries, tasks, hashtags | Next cycle prompts |

The executor prompt's `## DIRECTIVE` section combines all these signals into one coherent instruction.
Nothing in this file is read by any OV5 component — it exists solely for the legacy skill router.

## Immutable Files

```
early-init.el
pre-early-init.el
lisp/eca-security.el
lisp/modules/gptel-ext-security.el
lisp/modules/gptel-ext-tool-confirm.el
lisp/modules/gptel-ext-tool-permits.el
eca/**
mementum/**
var/elpa/**
```