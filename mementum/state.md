# Mementum State

> Last session: 2026-05-15

## Current Session: Marker-Derived Architecture

**Status:** Completed marker-derived toolset architecture + regression tests. All tool classification now flows from `nucleus-tool-markers` as single source of truth.

**Completed:**
- Converted `nucleus-toolsets` from hardcoded `defconst` to derived system: `nucleus-toolset-definitions` uses `(:derived INCLUDE EXCLUDE)` for primary toolsets, hand-curated lists for subagent roles
- Derived sandbox tool lists from markers (`gptel-sandbox.el`): 3 defcustoms now compute defaults from markers via `gptel-sandbox--default-{allowed,readonly,confirming}-tools`
- Updated `gptel-sandbox--current-profile` to check `:can-edit` marker availability
- Memory tools (`read_memory`, `write_memory`, `list_memories`) now included in all sandbox profiles automatically
- Added marker-conditional prompt injection to `nucleus-prompts.el`: memory and web instructions appended to agent system prompt based on marker tool registration
- Progressive shortening added to Code_Inspect (full → 30 lines → 10 lines) and Diagnostics (full → errors-only → count summary)
- Regression tests for: caar/cadr retry patterns, cons vs list pair construction, plist-dedup-put, toolset derivation from markers, sandbox profiles derived from markers
- Updated toolset count tests: readonly=20, nucleus=31, executor=30, researcher=19

**Commits:**
- `f8593e9a` — Derive sandbox profiles + progressive shortening
- `e5ba169c` — Update toolset counts + regression tests

**Remaining:**
- Grep tool progressive shortening (async, more complex)
- `normalize-controller-rules` plural wrapper cleanup (low severity)
- Per-project readonly override via `.dir-locals.el`

---
