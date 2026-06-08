---
title: Disposable Tracker
status: active
category: auto-workflow
tags: [yc, auto-workflow, disposable, regeneration, module-tracking, context-database]
related: [gptel-auto-workflow-code-regeneration, gptel-auto-workflow-context-database]
---

# Disposable Tracker

> Track which modules are candidates for code regeneration. Persists to `var/disposable/<module-slug>.sexp` sidecar files. Survives daemon restarts.

## Purpose

The disposable tracker identifies modules that have stagnant improvement (low score delta over many experiments) and marks them as "disposable" — candidates for full regeneration when a better model becomes available. It persists tracking state to `.sexp` sidecar files under `var/disposable/`, ensuring tracking survives Emacs daemon restarts. The auto-detection function scans the context database for modules with sufficient history (≥5 experiments by default) but below-threshold improvement (≤0.05 score delta), and marks them with metadata including `:best-delta`, `:experiment-count`, and `:marked-at` timestamp.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow-disposable-mark` | Mark a module as disposable with optional props; writes sidecar .sexp file |
| `gptel-auto-workflow-disposable-unmark` | Remove disposable tracking for a module; deletes the sidecar file |
| `gptel-auto-workflow-disposable-read` | Read disposable tracking entry for a module; returns plist or nil |
| `gptel-auto-workflow-disposable-list` | Return list of all tracked disposable modules |
| `gptel-auto-workflow-disposable-status` | Return status of a module: `:disposable`, `:persistent`, or `:unknown` |
| `gptel-auto-workflow-disposable-auto-detect` | Scan context database for modules with stagnant improvement; auto-mark candidates |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow-disposable-dir` | `"var/disposable"` | Directory for disposable module tracking sidecar files |
| `gptel-auto-workflow-disposable-min-experiments` | `5` | Minimum experiments before a module is considered for disposable tracking |
| `gptel-auto-workflow-disposable-max-delta` | `0.05` | Maximum score delta for a module to be marked disposable (stagnant improvement) |

## Integration Points

- **Code Regeneration**: The disposable tracker identifies modules for regeneration; the code-regeneration module executes the actual regeneration experiments.
- **Context Database**: `auto-detect` queries `gptel-auto-workflow-context-db-query` to scan historical experiment data for stagnant modules.
- **Worktree Base Root**: Uses `gptel-auto-workflow--worktree-base-root` (when available) to locate the disposable directory, falling back to `user-emacs-directory`.

## Test Coverage

No dedicated test file found. Sidecar persistence is tested implicitly through read/write round-trips.