---
name: auto-workflow
description: |
  Master skill for the automated code improvement workflow. Orchestrates experiment execution,
  result analysis, and skill evolution. Loads domain knowledge from other skills to avoid
  hardcoding prompts and rules.
version: 2.0
updated: 2026-05-08 19:04
metadata:
  category: orchestration
  author: auto-workflow
  depends-on:
    - eight-keys-grader
    - elisp-validator
    - provider-error-analyzer
    - sandbox-profiles
    - benchmark-improver
---
metadata:
  evolution-stats:
    total-experiments: 870
    last-evolution: 2026-05-08 18:52

---

# Auto-Workflow Master Skill

This is the orchestration skill for the automated code improvement system. It delegates domain knowledge to specialized skills rather than hardcoding rules.

## Domain Knowledge Skills

The workflow loads these skills dynamically. If a skill is missing, it falls back to hardcoded defaults.

### eight-keys-grader
- **Purpose**: Score code quality using φ/fractal/ε/τ/π/μ/∃/∀ framework
- **Loaded by**: `gptel-benchmark-principles.el`
- **Contains**: Key definitions, weights, signals, anti-patterns
- **File**: `assistant/skills/eight-keys-grader/SKILL.md`

### elisp-validator
- **Purpose**: Validate Emacs Lisp code before acceptance
- **Loaded by**: `gptel-tools-agent-validation.el`
- **Contains**: Validation rules for cl-return-from, undefined symbols, etc.
- **File**: `assistant/skills/elisp-validator/SKILL.md`

### provider-error-analyzer
- **Purpose**: Map provider errors to retry strategies
- **Loaded by**: `gptel-tools-agent-error.el`
- **Contains**: Error patterns, categories, recovery actions
- **File**: `assistant/skills/provider-error-analyzer/SKILL.md`

### sandbox-profiles
- **Purpose**: Define tool permission profiles per execution mode
- **Loaded by**: `gptel-sandbox.el`
- **Contains**: Allowed/readonly/confirming tool lists per profile
- **File**: `assistant/skills/sandbox-profiles/SKILL.md`

### benchmark-improver
- **Purpose**: Wu Xing-based auto-improvement rules
- **Loaded by**: `gptel-benchmark-auto-improve.el`
- **Contains**: Element-specific improvement suggestions
- **File**: `assistant/skills/benchmark-improver/SKILL.md`

### meta-harness-proposer
- **Purpose**: Generate new prompt-building strategies
- **Loaded by**: `gptel-tools-agent-strategy-evolver.el`
- **Contains**: Strategy generation prompts, anti-overfitting rules
- **File**: `assistant/skills/meta-harness-proposer/SKILL.md`

## Loading Pattern

```elisp
;; Standard skill loader
defun gptel-auto-workflow--load-skill-content (skill-name)
  "Load SKILL-NAME content using gptel-agent-read-file."
  (when (fboundp 'gptel-agent-read-file)
    (let ((skill-path (format "assistant/skills/%s/SKILL.md" skill-name)))
      (when (file-exists-p skill-path)
        (with-temp-buffer
          (insert-file-contents skill-path)
          (buffer-string))))))

;; Usage with fallback
defconst gptel-error--hard-quota-pattern
  (or (car (gptel-error--load-patterns-from-skill))
      "allocated quota exceeded|insufficient_quota|...")
```

## Self-Evolution Pipeline

```
experiments/ → analyze_results.py → analysis.json
                     ↓
            evolve_skills.py (SKILL_REGISTRY)
                     ↓
    ┌────────┬────────┬────────┬────────┬────────┐
    ↓        ↓        ↓        ↓        ↓        ↓
 sandbox  eight-   elisp-   provider benchmark auto-
profiles  keys    validator  error    improver  workflow
    │        │        │        │        │        │
    └────────┴────────┴────────┴────────┴────────┘
                     ↓
              Updated SKILL.md files
                     ↓
              Emacs loads new rules
                     ↓
              Next experiment batch
```

## Experiment Stats

- **Total experiments**: 870
- **Targets tracked**: 36
- **Average keep rate**: 14%
- **Top target**: gptel-tools-agent-staging-baseline.el (33% keep rate)

## Token Efficiency

- **Average prompt size (kept)**: 18064 chars
- **Average prompt size (discarded)**: 18809 chars
- **Optimal range**: Shorter prompts perform better

## Section A/B Tests

- **all sections**: 21% success rate (105/512)

## Key Principles

1. **Never hardcode domain knowledge** — put it in skills
2. **Skills must be self-describing** — frontmatter with name, version, dependencies
3. **Evolution is data-driven** — analyze experiments, update skills, repeat
4. **Fallback to defaults** — if skill missing, use hardcoded defaults
5. **Git-based persistence** — skills live in repo, versioned with commits
