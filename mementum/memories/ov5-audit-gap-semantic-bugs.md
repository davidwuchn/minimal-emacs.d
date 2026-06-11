# OV5 Audit Gap: Static Checks Miss Runtime Bugs

## Insight
OV5 self-heal-semantic has 7 audit checks but they are all *static pattern matching* — they catch structural bugs (missing parens, missing provide, unguarded calls) but miss *runtime semantic bugs* (wrong type comparisons, incorrect control flow logic, void-variable in batch mode).

## Evidence
5 bugs caught by human-session agent that OV5 auto-heal did NOT detect:
1. `eq "success" 'symbol` — string vs symbol type mismatch in plist comparison
2. `if(and(<retries fboundp))` — retry coupled to self-heal availability
3. `defvar` without default — void-variable only in batch mode
4. brepl validate-brackets return value mismatch
5. test ordering pollution from fmakunbound leaking across tests

All 5 passed check-parens + load-file. Only the test suite caught them.

## Fix (wave 1)
Added `gptel-auto-workflow--run-ert-in-worktree` — calls `scripts/run-tests.sh unit` in the worktree before promotion.

## Fix (wave 2 — P0 regression)
The gate had an inverted-logic bug: regex `"FAILED\\|failed\\|unexpected"` matched "0 unexpected" (the PASS string from ERT). Result: gate rejected ALL promotions, including correct ones. The mock tests didn't catch it because they used synthetic output, not real ERT text.

Root cause: `shell-command-to-string` discards exit code, so the gate relied on output text parsing with a broken regex. Fix: replaced with `call-process` (captures stdout+stderr in buffer+file, returns exit code). Now pass/fail is based on exit code, not text matching.

## Pattern
Auto-evolution pipelines need *runtime validation* (test execution), not just static validation (syntax checking). The gap between "parses correctly" and "behaves correctly" is where semantic bugs live.
