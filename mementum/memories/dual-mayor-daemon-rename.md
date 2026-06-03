---
title: Dual Mayor Daemon Rename — pmf-value-stream + gtm-product-org
created: 2026-06-03
tags: [dual-mayor, rename, daemon, PMF, GTM]
---

## Rename

Old names: `ov5-auto-workflow`, `ov5-researcher`
New names: `pmf-value-stream`, `gtm-product-org`

## Rationale

Names now match the pattern languages they implement:
- **PMF Mayor** = Value Stream Pattern Language = `pmf-value-stream`
- **GTM Mayor** = Product Organization Pattern Language = `gtm-product-org`

## Files Updated

1. `scripts/run-auto-workflow-cron.sh` — default SERVER_NAME values
2. `scripts/run-pipeline.sh` — socket names, log rotation, cleanup
3. `scripts/watchdog-daemon.sh` — SERVER_NAME default + researcher PID
4. `lisp/modules/gptel-auto-workflow-strategic.el` — researcher-daemon-p
5. `lisp/modules/gptel-auto-workflow-projects.el` — shutdown function
6. `lisp/modules/gptel-auto-workflow-evolution.el` — log file path

## Backward Compatibility

- Old names (`ov5-auto-workflow`, `ov5-researcher`) still accepted via:
  - `AUTO_WORKFLOW_EMACS_SERVER` env var
  - `daemonp` return value
  - `server-name` variable
- Pipeline pgrep matches both old and new names
- Tests use old names (test-specific, not runtime)

## Tests

2149 tests, 2097 expected, 0 unexpected, 52 skipped — all pass.
