# Agentic Pattern Research — Turn 1/4

## Architecture Overview

The codebase implements a **layered agentic architecture** across 15+ split modules controlling tool dispatch, state management, and async workflows.

## Pattern 1: Tool Dispatch with Defensive Guards

**File**: `gptel-ext-tool-sanitize.el`
- **Fuzzy tool name matching**: Normalizes case, underscores/hyphens via `my/gptel--normalize-tool-name` before comparison. Three-tier: exact → case-insensitive → normalized.
- **Doom-loop detection** (`my/gptel--detect-doom-loop`): Track fingerprint=name+md5(args) per tool call. When same fingerprint repeats N=5 times, abort turn by advancing FSM to DONE. Mirrors OpenCode's DOOM_LOOP_THRESHOLD=3 but raised due to TodoWrite repeats.
- **Inspection thrash** (`my/gptel--detect-inspection-thrash`): Track consecutive read-only inspections on same file. File-size-aware threshold (base 40 + extra from file size). Progressive: warn@50% → urgent@75% → abort@100%.
- **Preset recovery**: When tool is missing from info:tools but known globally, inject it dynamically and log once.
- **Error wrapping**: `:around` advice on `gptel--handle-tool-use` catches dispatch errors and stamps them as tool results.

**Applicable to**: Any agentic workflow. Add inspection-thrash detection to prevent infinite read loops. Add doom-loop detection with hash-keyed fingerprints.

## Pattern 2: State Management via FSM Registry

**File**: `gptel-ext-fsm-utils.el`
- **Bidirectional FSM↔ID registry**: Weak-valued hash table prevents GC of unreferenced FSMs. Two maps: FSM→ID and ID→FSM for O(1) lookup.
- **ID format**: `fsm-N-TIMESTAMP` where N=sequential counter, timestamp=epoch seconds. Dual-component ensures uniqueness even with rapid creation.
- **Context-aware coercion** (`my/gptel--coerce-fsm-with-context`): When multiple FSMs exist, returns most recently registered (child FSM preference). Fixes nested subagent scenario where wrong parent FSM was selected.
- **Cycle-safe traversal**: Hash table of seen objects prevents infinite loops in dotted pairs and circular structures.
- **Registry validation**: 4 invariants checked: bidirectional consistency, unique IDs, ID format, FSM coverage.

**Applicable to**: Any nested agent architecture needing correct FSM selection. The ID-based registry pattern avoids parent-child confusion without explicit nesting tracking.

## Pattern 3: Timeout Architecture with Two-Level Deadlines

**File**: `gptel-tools-agent-subagent.el`
- **Idle timeout**: Timer rearms on each activity. If no activity for N seconds → abort.
- **Hard deadline**: Absolute wallclock timeout from dispatch. Whichever fires first wins.
- **Remaining-time calculation**: `(max 0 (ceiling (float-time (time-subtract hard-deadline (current-time)))))` ensures hard deadline is always checked.
- **Safe callback** (`my/gptel--invoke-callback-safely`): Catches all errors. Uses isolated `*gptel-callback*` buffer. Falls back to `run-at-time` in noninteractive mode (needed for emacsclient --batch).
- **Overlap cleanup** (`my/gptel--cleanup-overlapping-agent-tasks`): Aborts stale timers/callbacks from older experiments on the same buffer/worktree before launching new ones.

**Applicable to**: Emacs async workflows with curl-based LLM requests. The two-level timeout (idle + hard) prevents both hung requests and cumulative run-away sessions.

## Pattern 4: Experiment Execution Lifecycle

**File**: `gptel-tools-agent-experiment-core.el`
- **Worktree isolation**: Each experiment gets a git worktree. default-directory bound to worktree so all subagents operate in context.
- **Pre-grade validation**: Syntax check ALL modified files (not just target) before calling grader API. Saves API costs on bad edits.
- **Teachable retry**: When validation fails with teachable pattern, re-runs executor with extra context about what went wrong.
- **Timeout salvage**: When executor times out with partial changes, evaluates actual worktree diff rather than discarding.
- **Repeated focus detection**: Same symbol attempted ≥2 prior times → skip grading entirely.

**Applicable to**: Code improvement workflows needing structured experiment lifecycle. Pre-grade validation before API calls is a key cost-saving pattern.

## Pattern 5: Tool Call Lifecycle Guards

**File**: `gptel-ext-tool-sanitize.el` (advice registration)
- Four pieces of `:before` advice on `gptel--handle-tool-use`: sanitize → doom-loop → inspection-thrash → error-wrap
- Tool dedup via `:around` advice on `gptel--parse-tools`: last-wins for duplicate tool names
- `my/gptel--abort-sanitized-turn`: Stamps error message on FSM, calls gptel-abort on live buffer

## Gaps Identified

1. **No backpressure mechanism**: Multiple experiments run in parallel with no throttling based on remaining quota.
2. **Error categorization not unified**: `gptel-tools-agent-error.el` has separate functions for rate-limit, auth, quota errors but no single classification dispatch.
3. **No circuit breaker**: Repeated failover between providers has no backoff pattern beyond immediate retry.
4. **Stale callback detection**: Uses string-based run-ID check but no TTL for stale results.

## Priority for Experimentation

Based on early-exploration stage and 0 experiments across all task types:
- **Best first task**: Validation/Safety (Axis A) — add a circuit breaker for provider failover
- **Second**: Refactoring (Axis F) — unify error categorization into single dispatch
- **Third**: Performance — reduce FSM registry overhead for deep nesting
