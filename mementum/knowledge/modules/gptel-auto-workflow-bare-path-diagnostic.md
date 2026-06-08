---
title: Bare Path Diagnostic
status: active
category: auto-workflow
tags: [yc, auto-workflow, self-heal, diagnostic, workspace, portability]
related: [gptel-auto-workflow-self-audit, gptel-tools-agent-base]
---

# Bare Path Diagnostic

> Pre-experiment bare-path detection for self-heal diagnostics. Scans .el source files for non-absolute string path literals used in I/O calls without workspace boundary expansion.

## Purpose

The bare-path diagnostic is a self-healing quality check that scans module source files for bare (non-absolute) string path literals used in dangerous I/O calls like `directory-files`, `with-temp-file`, `find-file`, and `insert-file-contents`. These are portability hazards: bare paths resolve relative to `default-directory`, which varies between batch mode and interactive sessions, causing silent failures. The diagnostic identifies violations with suggested fixes (wrapping in `gptel-auto-workflow--expand-workspace-path`), reports them as Phase 0 of self-heal, and leaves fixes for human approval — it never auto-applies changes.

## Public Functions

| Function | Purpose |
|----------|---------|
| `gptel-auto-workflow--diagnose-bare-paths` | Scan .el files in a module directory for bare path violations; return list of violation plists |
| `gptel-auto-workflow--self-heal-bare-paths` | Run diagnostic and report violations as Phase 0 of self-heal; returns `:violations-found`, `:fixes-applied` (always 0), `:violations` |

## Key Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `gptel-auto-workflow--bare-path-dangerous-functions` | `("directory-files" "with-temp-file" "find-file" "insert-file-contents")` | List of I/O function names that should not receive bare string path literals |

## Integration Points

- **Self-Heal Pipeline**: Designed to be called as Phase 0 of self-heal (before experiments run). Fixes are diagnostic-only; human must approve.
- **Workspace Boundary**: Uses `gptel-auto-workflow--expand-workspace-path` to determine the scan directory and generate suggested fixes.
- **Violation Detection Rules**: Flags a string literal as a bare path if (a) it is NOT absolute, (b) the call is NOT already wrapped in `expand-file-name` with a root, (c) the call is NOT already wrapped in `gptel-auto-workflow--expand-workspace-path`, and (d) the line is NOT a comment.

## Test Coverage

No dedicated test file found. The diagnostic is a read-only scan; it never modifies source files.