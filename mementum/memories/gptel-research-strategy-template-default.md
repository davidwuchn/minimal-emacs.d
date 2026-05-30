# Research Strategy: template-default

## 204 experiments across 30 files
Core pattern: validate inputs early, handle nil gracefully, make implicit assumptions explicit.

## Kept Hypothesis Categories (29 total)

### Input Validation (Safety/Correctness)
- `gptel-auto-experiment--validate-candidate-safely`: nil/non-string/empty guards
- `gptel-auto-workflow-research-status-all`: nil safety for project data
- `gptel-workflow--score-tools`: proper-list-p validation
- `gptel-benchmark-summarize-results`: proper-list-p + nil guards
- `gptel-benchmark-prescribe`: nil guard for malformed plist entries
- `gptel-auto-workflow--finalize-review-fix-result`: nil validation for response
- `gptel-tools-memory--collect-dir`: empty-string topic fix, TYPE-LABEL validation
- `gptel-tools-memory--resolve-path`: slug char validation, knowledge-p type validation, file-name-absolute-p path traversal prevention

### Data Structure Bugs
- `gptel-benchmark--to-json-format`: keyword-to-alist conversion bug (dotted-pair alists)
- `gptel-benchmark--to-json-format`: `(cl-every #'consp data)` validation for alist processing
- `gptel-benchmark-diagnose-elements`: alist-get vs plist-get fix (scores always defaulted to 0.5)
- `gptel-benchmark--extract-scores`: proper extraction of `:scores` from alist JSON results

### Error Handling
- `gptel-tools-memory--read`: file-regular-p validation, signal errors instead of returning strings
- `my/gptel--sync-to-upstream`: error handling for buffer iteration failures
- `my/gptel-permit-tool`: input validation for hash table safety

### Performance Optimizations
- `gptel-auto-workflow--link-shared-runtime-path`: stale-copy bug fix (treats regular files as invalid without creating symlinks)
- `gptel-benchmark-summarize-results`: extract `gptel-benchmark--empty-summary` helper
- `gptel-benchmark-baseline-file-compare`: swap argument order (version-a=current, version-b=baseline → inverts improvement signals)

### Testing/Quality
- `gptel-benchmark-tests.el`: move 14 tests from after `provide` to before, add unwind-protect for global state, require cl-lib
- `gptel-tools-agent.el`: hash-table-keys not built-in - must implement
- `gptel-workflow-load-tests`: error-message-string formatting

## Discarded Hypotheses (50+)

### Already Optimized
- `gptel-ext-tool-permits.el`: already at 139 lines (from 200), all optimizations done
- `nucleus-prompts.el`: directory resolution already efficient enough

### Memoization Rejected
- `nucleus--project-root`: caching unnecessary
- `nucleus--resolve-prompts/agents/tool-prompts-dir`: caching rejected
- `gptel-auto-workflow--safe-backend-name`: 18 call sites but caching not worth it

### Minor/Incorrect
- `nucleus--validate-contract`: argument order not actually buggy
- `condition-case` in `gptel-auto-workflow--safe-truename`: `(ignore)` actually works
- Removing redundant `(cl-every #'consc data)`: double-pass not worth micro-optimizing
- Various indentation fixes: misleading but not actually buggy

## Key Insights

1. **Nil validation is highest-value hypothesis type** - 40%+ of kept hypotheses
2. **Data structure mismatches (alist vs plist) are common bugs** - especially in benchmark code
3. **File structure bugs (code after provide)** are subtle but real in batch mode
4. **Memoization rarely pays off** - only when filesystem calls dominate
5. **Keep validation functions atomic** - separate guards for each concern
