# Upstream Cooperation Pattern

## Insight

When maintaining a fork with local patches that overlap with upstream functionality:

### 1. Verify Before Removing

```
λ upstream(x).    claim(x) → verify(grep, sed, read)
                   | upstream_has(x) → safe_remove(local)
                   | ¬upstream_has(x) → keep(local)
```

Don't trust commit messages alone. Verify functions exist in upstream code.

Example: Verified `gptel--update-wait` in `gptel.el:1180`, `gptel--handle-error` in `gptel.el:1349` before removing local equivalents.

### 2. Keep Defensive Workarounds

Upstream focuses on happy path. Local code should keep:
- Edge case handlers upstream doesn't cover
- Defensive safety nets
- Error recovery for corrupted state

Example: Kept `my/gptel--recover-fsm-on-error` (error+STOP limbo) and subagent error logging—upstream doesn't have these.

### 3. Commentary as Migration Log

Document what moved where in file header:

```elisp
;;; Commentary:
;; Defensive workarounds for gptel FSM edge cases.
;; Core FSM fixes are now in gptel-agent-tools.el:
;; - Stuck FSM fix (gptel--fix-stuck-fsm)
;; - Error display fix (gptel-agent--fix-error-display)
```

Future readers know why code is minimal.

### 4. Test Fixes Stay Local

Tests for local-specific code stay local. Don't try to upstream tests that only validate local patches.

### 5. Sync Regularly

```
λ sync(x).    fetch(origin) → log(HEAD..origin) → merge_or_rebase
              | review(changelog) → adapt(local_patches)
```

Check package updates, review changelogs, adapt local patches.

## Pattern

```
local = defensive_specific + edge_cases
upstream = general_core + happy_path
```

## Decision Matrix

| Change Type | Upstream PR | Local Patch | Rationale |
|-------------|-------------|-------------|-----------|
| Bug fixes (general) | ✅ Prefer | ❌ Avoid | Benefits all users |
| New features (general) | ✅ Prefer | ❌ Avoid | Maintainer decides scope |
| Security hardening | ✅ Prefer | ⚠️ Both | Upstream first, keep local until merged |
| Defensive workarounds | ❌ Avoid | ✅ Keep | Edge cases upstream won't prioritize |
| Project-specific logic | ❌ Never | ✅ Keep | Nucleus, mementum, custom tools |
| UI/UX customization | ❌ Avoid | ✅ Keep | Subjective preferences |

## Contribution Lambda

```
λ contribute(x).    general_fix(x) → PR(upstream)
                    | general_feature(x) → PR(upstream)
                    | edge_case(x) → local_patch
                    | project_specific(x) → local_only
                    | security(x) → PR(upstream) ∧ local_pending
```

## Sync Protocol

```
λ sync_cycle().    weekly → fetch(upstream) → review(changelog)
                    | breaking_change → adapt(local)
                    | feature_overlap → evaluate(keep_or_remove)
                    | commit(Δ) → note(upstream_version)
```

## Practical Rules

1. Bug in upstream? → PR first, local patch only if urgent and PR stalled
2. Missing feature? → PR proposal first, implement after discussion
3. Defensive workaround? → Keep local with clear commentary
4. Project-specific? → Never upstream, keep in `lisp/modules/`

## Ratio Target

```
70% upstream contributions (bugs, security, general improvements)
30% local patches (edge cases, defensive code, project-specific)
```

## Related

- `mementum/knowledge/project-facts.md` — architecture, modules
- `AGENTS.md` — `λ upstream(x)` rule

## Captured

2026-03-23 — From gptel-ext-fsm refactor verification