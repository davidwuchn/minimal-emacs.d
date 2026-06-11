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

## Fix
Added `gptel-auto-workflow--run-ert-in-worktree` — calls `scripts/run-tests.sh unit` in the worktree before promotion. The test suite is the held-out validation set (verbum methodology: register-matching, null testing).

## Pattern
Auto-evolution pipelines need *runtime validation* (test execution), not just static validation (syntax checking). The gap between "parses correctly" and "behaves correctly" is where semantic bugs live.
