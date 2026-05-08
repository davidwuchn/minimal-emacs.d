# 💡 skill-extraction-pattern

**Status:** ✅ Merged | **Date:** 2026-05-08

## What We Learned

~600 lines of hardcoded domain knowledge in Emacs Lisp modules extracted into 5 editable markdown skills.

## Why It Matters

Skills evolve via Python scripts without recompiling Emacs. Humans can edit them. System loads them dynamically.

## The Pattern

```
λ extract(x).
  grep constants/lists/prompts in .el files
  → create SKILL.md with frontmatter
  → add loader: gptel-auto-workflow--load-skill-content
  → fallback to hardcoded defaults if skill missing
```

## Skills Created

- `sandbox-profiles` — tool permission profiles
- `eight-keys-grader` — Wu Xing scoring rubric
- `elisp-validator` — code validation rules
- `provider-error-analyzer` — error pattern matching
- `benchmark-improver` — benchmark analysis prompts

## Evolution Pipeline

```
analyze_results.py → evolve_*.py → updated SKILL.md with stats
```

## Key Insight

Hardcoded knowledge is dead knowledge. Externalized skills are living knowledge that can self-evolve.
