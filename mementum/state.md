# Mementum State

> Last session: 2026-05-11 17:25

## Current Session: 2026-05-11 CF-Gateway Kimi K2.6 Executor Default

**Status:** CF-Gateway executor fallback now targets Cloudflare Workers AI Kimi K2.6 locally. Main/staging pipeline commits were already pushed earlier; current worktree has uncommitted CF-Gateway fallback edits plus unrelated auto-workflow generated skill/strategy files.

**Done:**
- Verified there are no `@cf/moonshotai/kimi-k2.5` references in tracked source/docs/tests.
- Referenced Cloudflare docs for `@cf/moonshotai/kimi-k2.6`: 262,144 token context, function calling yes, reasoning yes, vision yes, pricing `$0.95/M` input, `$0.16/M` cached input, `$4.00/M` output.
- Updated executor rate-limit fallback default: `CF-Gateway` now uses `@cf/moonshotai/kimi-k2.6`.
- Kept headless non-executor CF-Gateway fallback on `@cf/openai/gpt-oss-120b` for cheaper/faster subagent fallback.
- Added Cloudflare Kimi K2.6 context-window and metadata entries.
- Added retry payload byte limits for `@cf/moonshotai/kimi-k2.6` and `kimi-k2.6`.
- Updated docs/tests to describe CF-Gateway Kimi K2.6 as the executor fallback.

**Verification:**
- `git diff --check` passed.
- `emacs --batch -Q -L lisp/modules -L packages/gptel -l tests/test-gptel-ext-context-cache.el -f ert-run-tests-batch-and-exit`: passed `40/40`.
- `emacs --batch -Q -L lisp/modules -L packages/gptel -l tests/test-gptel-ext-retry.el -f ert-run-tests-batch-and-exit`: passed `41/41`.
- Targeted fallback regression command with `var/elpa/yaml-1.2.3`: `1/1` passed, legacy migration test skipped as pre-existing flaky skip.
- Byte-compile touched modules passed with existing declaration/docstring warnings.

**Current Worktree:**
- Intended CF/Kimi files modified: `INTRO.md`, `docs/auto-workflow.md`, `docs/directive.md`, `lisp/modules/gptel-ext-backends.el`, `lisp/modules/gptel-ext-context-cache.el`, `lisp/modules/gptel-ext-retry.el`, `lisp/modules/gptel-tools-agent-prompt-build.el`, `tests/test-gptel-ext-context-cache.el`, `tests/test-gptel-tools-agent-regressions.el`.
- Unrelated generated edits still present and should not be mixed into the CF-Gateway commit unless explicitly requested: `assistant/skills/auto-workflow/SKILL.md`, `assistant/skills/auto-workflow/token-efficiency.md`, `assistant/strategies/metadata/band-compression.json`, `assistant/strategies/prompt-builders/strategy-band-compression.el`.

**Next Steps:**
- Optionally live-test CF-Gateway Kimi K2.6 through curl/gptel.
- Review diff and commit only intended CF/Kimi files if requested.
- Merge/push to staging after main commit if requested.
