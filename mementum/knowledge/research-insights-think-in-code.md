---
title: Research Insights - Think in Code
status: active
category: knowledge
tags: [research, paradigm, context-optimization]
insight-quality: 9/10
---

# Think in Code Paradigm

*From context-mode's ctx_execute. Key insight for context optimization.*

## Principle

**Program the analysis, not compute it.**

Instead of chaining 10+ tool calls (Read, Grep, Bash) that flood context, write ONE script that processes data and outputs ONLY the result.

## Example

```
// Before: 47 × Read() = 700 KB context
// After:  1 × Bash(python script) = 3.6 KB context

python3 << 'EOF'
import os
for f in os.listdir('src'):
    if f.endswith('.el'):
        lines = open(os.path.join('src', f)).read().split('\n')
        print(f"{f}: {len(lines)} lines")
EOF
```

## Application for Emacs AI

| Pattern | Current | Better |
|---------|---------|--------|
| Count functions | `Grep defun` + parse | Python script: regex count |
| Analyze git history | `Bash git log` 50KB | Script: aggregate by author |
| Find patterns | 20× `Grep` calls | Script: single pass with counters |
| Compare files | 10× `Read` + diff | Script: hash + compare |

## Success Metrics

- **96-98% context reduction** (context-mode benchmarks)
- **One tool call** replaces 10-50 calls
- **Stdout only** - stderr logged separately

## Recommended Targets

- `gptel-auto-workflow-strategic.el` — git history analysis
- `gptel-benchmark-evolution.el` — score aggregation
- Researcher subagent — web content processing

## Source

- `davidwuchn/context-mode` README.md
- Benchmark: 315 KB → 5.5 KB (98% reduction)