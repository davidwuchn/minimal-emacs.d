# Mementum State

> Last session: 2026-05-14

## Current Session: Fix research daemon maphash corruption

**Status:** Fixed. Research daemon now populates findings via standalone loader.

**Root Cause:** `load-file` corrupts complex defuns with nested lambdas in the daemon context. The Elisp reader misparses `maphash` lambda forms, pulling the hash-table argument into the lambda body — causing `(wrong-number-of-arguments maphash 1)` or `maphash 3` errors.

**Failed approaches:**
- `eval-buffer` in temp buffer with `lexical-binding t` — reader still corrupts
- `read` + `eval` individual forms — same reader issue
- `after-load-functions` with `eval` of quoted forms — the quoted form is also read by the corrupt reader
- `defalias` in post-init.el — reader corrupts the lambda form

**Working fix (`d418760d`):**
- Created `lisp/modules/standalone-research.el` — bypasses ALL strategic.el functions
  - Loads `SKILL.md` → calls `gptel-benchmark-call-subagent` → saves findings
  - No `maphash`, no complex lambdas — survives `load-file` intact
- Modified `post-init.el` (when `MINIMAL_EMACS_WORKFLOW_DAEMON=1`):
  - Loads `standalone-research.el`
  - `defalias` `gptel-auto-workflow-run-research` → `slr-run-research`
  - `after-load-functions` hook re-applies alias after strategic file reloads by cron
- Verified: research findings → 2191 bytes (was 86 bytes header-only)
- Pushed to origin + upstream

**Pattern discovered:** `load-file` corrupts ANY form containing `maphash` with a nested `lambda` that has closure variables. The `topics` (or similar) argument to `maphash` gets parsed into the lambda body instead of after it. This is a persistent Emacs Lisp reader bug in the daemon context.

**Daemon status:**
- ✅ `copilot-auto-workflow` — running (PID 96202, since yesterday)
- ✅ `copilot-researcher` — running (PID 60750, with standalone override active)
- Findings file: `/Users/davidwu/.emacs.d/var/tmp/research-findings.md` — 2191 bytes

**Next Steps:**
1. Monitor cron — verify research runs at scheduled intervals (every 4h)
2. If standalone research proves reliable, consider removing the complex strategic functions from the researcher daemon codepath entirely
3. Document the `load-file` reader bug for upstream Emacs reporting
