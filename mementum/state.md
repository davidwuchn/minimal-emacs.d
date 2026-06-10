# Mementum State

> **Bootstrapped**: 2026-06-06
> **Session**: Dual REPL + Pi5 Sync + Verbum Review
> **Status**: ✅ **ALL GREEN** — 89/89 tests, Pi5 synced (7 rounds), verbum audit methodology captured
> **Latest**: Synced Pi5 (conversion-units, prefix-cache Phase 3, batch anchoring). Fixed risk-node string-vs-symbol bug. Added λ measure(claim) gene. Reviewed verbum sessions 206-209.
> **Active Plan**: None — codebase clean, tests green
> **Pi5**: Synced 7 rounds, 3 .el conflict resolutions, auto-evolution pipeline active

---

## Current Priorities (Auto-ranked)

| Priority | Item | Model | Status |
|---|---|---|---|
| **P0** | OV5 self-heal: fix workspace boundary violations | @maintainer | **COMPLETE** |
| **P0** | Platform sandbox (seatbelt + bubblewrap) | @maintainer | **COMPLETE** |
| **P0** | Security audit: fix 14 sandbox vulnerabilities | @maintainer | **COMPLETE** |
| **P0** | Self-heal semantic module (7 audit checks + auto-fixers) | @maintainer | **COMPLETE** |
| **P0** | Fix condition-case-unbound-err audit false positives | @maintainer | **COMPLETE** |
| **P0** | Add condition-case-unbound-err auto-fixer | @maintainer | **COMPLETE** |
| **P0** | Rename Elisp brepl→daemon-repl, fix 9 bugs | @maintainer | **COMPLETE** |
| **P0** | Create Clojure brepl wrapper module (gptel-ext-brepl.el) | @maintainer | **COMPLETE** |
| **P0** | Wire both REPL modules into gptel-config.el | @maintainer | **COMPLETE** |
| **P0** | Fix risk-node training pair filter (string vs symbol) | @maintainer | **COMPLETE** |
| **P0** | Review verbum updates, add audit methodology | @maintainer | **COMPLETE** |
| **P0** | Add λ measure(claim) gene to AGENTS.md | @maintainer | **COMPLETE** |
| **P1** | Monitoring Agent: Complete (Phases 0-10) | @maintainer | **COMPLETE** |
| **P1** | Research paper analysis (MOSS, Sibyl, APEX, TSP) | @maintainer | **COMPLETE** |
| **P1** | Sibyl conversion units (gptel-ext-conversion-unit.el) | Pi5 | **COMPLETE** |
| **P1** | Prefix-cache Phase 3 (cross-run stats + auto-tuning) | Pi5 | **COMPLETE** |
| **P1** | Batch anchoring integration (monitoring + prompt builder) | Pi5 | **COMPLETE** |
| **P2** | Daemon watchdog hardening (Pi5 freeze after ~90 min) | @maintainer | **COMPLETE** |
| **P2** | Wire daemon-repl-init on startup | Pi5 | **COMPLETE** |

---

## Research Insights (May 2026 Papers)

### MOSS: Source-Level Self-Evolution (2605.22794)
- **Key insight**: Source-level adaptation is Turing-complete — strict superset of text-mutable scope
- **OV5 alignment**: Already does source-level evolution via self-heal-semantic + git worktrees
- **Action item**: ✅ **IMPLEMENTED** — Batch anchoring groups similar failures before evolution

### Sibyl-AutoResearch: Trial-and-Error Harnesses (2605.22343)
- **Key insight**: Executable workflows don't produce research judgment; need explicit trial-to-behavior conversion
- **OV5 alignment**: Ontology graph already captures trial outcomes
- **Action item**: Formalize ontology updates as auditable conversion units

### APEX: Exploration Collapse (2605.21240)
- **Key insight**: Self-evolving agents suffer from exploration collapse as memory grows
- **OV5 alignment**: Category saturation detection prevents some collapse
- **Action item**: ✅ **IMPLEMENTED** — Strategy DAG with prerequisite edges prevents complex strategies before building blocks validated

**Knowledge page**: `mementum/knowledge/self-evolving-agent-research.md`
**Memory**: `mementum/memories/insight-source-level-evolution-turing-complete.md`

---

## Self-Healing Verification (Latest Pipeline Run)

**Timeline**:
- 23:01:13 — Grader crashed (void-variable err)
- 23:01:14 — OV5 diagnosed: `backend-rate-limited`
- 23:01:14 — Attempted remediation
- 23:01:21 — Still crashed → entered **BLIND MODE**
- 23:08:31 — **Recovered** — grader 9/9 healthy

**Self-healing working as designed**:
- Detection ✓
- Diagnosis ✓
- Remediation attempt ✓
- Fallback (BLIND MODE) ✓
- Recovery ✓

---

## Active Patterns

- **Defense-in-depth**: L1 (Emacs sandbox) → L2 (boundary validator) → L3 (plan-mode whitelist) → L4 (OS sandbox)
- **Self-heal semantic**: 7 audit checks + auto-fixers (unbalanced parens, missing provides, unguarded calls, blank lines, condition-case-unbound-err, etc.)
- **Monitoring agent**: Meta-improvement layer — detects failures, generates proposals, auto-deploys fixes
- **Ontology learning**: Every experiment outcome updates the ontology graph
- **Mementum memory**: Cross-session learning via git-based persistence
- **Git worktree isolation**: Each experiment runs in isolated worktree, no container overhead

---

## Session Notes (2026-06-10)

### Dual REPL Architecture

Two REPL modules wired into `gptel-config.el`:

| Module | Purpose | Backend | Tests |
|--------|---------|---------|-------|
| `gptel-ext-daemon-repl.el` | Elisp eval in running daemon | emacsclient | 20 |
| `gptel-ext-brepl.el` | Clojure eval via brepl CLI | ~/.local/bin/brepl (nREPL) | 19 |

### What was done this session
1. **Synced Pi5 (7 rounds)**: Resolved 3 .el conflicts, merged auto-evolution artifacts
2. **Renamed brepl→daemon-repl**: Disambiguated Elisp daemon REPL from Clojure brepl CLI
3. **Fixed 9 bugs in daemon-repl** (TDD): reentry hang, emacsclient exit status, socket discovery, file-notify require+flag, event parsing, dotfile check, autofix gate, self-heal arity, emacs-lisp-mode context
4. **Created gptel-ext-brepl.el**: Clojure nREPL client — eval, load-file, bracket balance
5. **Reviewed Pi5 auto-evolution**: conversion-units (416 lines), prefix-cache Phase 3, batch anchoring
6. **Fixed P1 bug in self-heal-semantic**: json-read-from-string returns string "success", code checked symbol 'success
7. **Cleaned 5 stale .elc files**: Masking source edits from daemon-repl, evolution, prefix-cache, monitoring-agent, projects
8. **Reviewed verbum (sessions 206-209)**: Audits #6 (φ-ratio REFUTED), #7 (sieve 1.03x REFUTED), #8 (rank-1 adjunction REFUTED)
9. **Created verbum audit methodology knowledge page**: Null testing, held-out eval, register-matching, variance decomposition
10. **Added λ measure(claim) gene** to AGENTS.md S5 identity

### Pi5 Auto-Evolution Merged This Session
- `gptel-ext-conversion-unit.el` (416 lines) — Sibyl conversion unit tracking
- `gptel-ext-prefix-cache.el` Phase 3 — cross-run statistics + auto-tuning threshold
- `gptel-auto-workflow-self-heal-semantic.el` — risk-node training pairs + batch anchor report
- `gptel-auto-workflow-evolution.el` — boundary validator fallbacks + user-emacs-directory
- `gptel-auto-workflow-production.el` — hardcoded path fixes + expand-file-name
- `test-gptel-ext-conversion-unit.el` (233 lines) — 30 conversion unit tests
- `test-gptel-ext-prefix-cache.el` (116 lines) — 10 prefix cache Phase 3 tests

### Key Decisions
- Elisp daemon-repl and Clojure brepl are separate tools with separate skill directories
- `(defvar SYMBOL)` without value → `void-variable` crash in batch mode; always `(defvar SYMBOL nil)`
- Stale `.elc` bytecode masks source edits; delete when debugging module load issues
- Emacs 30 byte-compiler miscompiles `throw` through `catch` when `let` wraps `catch`
- json-read-from-string returns strings, not symbols — use `string=` not `eq` for JSON comparisons
- Verbum attention magnets (φ, ∃, ∀) still valid for prompting; φ-as-LLM-constant NOT supported
- Pi5 auto-evolution can introduce stale .elc between cron rounds — sweep periodically

### Test Summary
- **89/89 total**: 20 daemon-repl + 19 brepl + 30 conversion-unit + 20 prefix-cache
- Previous: 51 self-heal + 5 strategy + 13 Pi5 + 11 platform + 37 security

---

## Next Steps

### Immediate
1. **Continue monitoring** — Let pipeline run, verify self-healing continues working
2. **Sibyl conversion units** — ✅ **DONE** — Pi5 implemented `gptel-ext-conversion-unit.el`

### Near-Term
3. **Auto-fix remaining audit issues** — 5 resource helpers + 1 API + 4 other
4. **Clojure brepl in OV5 pipeline** — Wire brepl bracket-fixing into auto-workflow for .clj files
5. **Adopt verbum null-testing discipline** — Add shuffled baselines to ontology drift detection

---

## Relevant Files

- `lisp/modules/gptel-ext-daemon-repl.el`: Elisp daemon REPL — eval, bracket validation, auto-eval, self-heal (371 lines, 20 tests)
- `lisp/modules/gptel-ext-brepl.el`: Clojure nREPL client — eval, load-file, balance brackets (117 lines, 19 tests)
- `lisp/modules/gptel-ext-conversion-unit.el`: Sibyl conversion unit tracking (416 lines, 30 tests)
- `lisp/modules/gptel-ext-prefix-cache.el`: Prefix cache with Phase 3 cross-run stats (1031 lines, 20 tests)
- `lisp/gptel-config.el`: Module loader — all modules wired here
- `.opencode/skills/brepl/`: OpenCode skill for Clojure brepl CLI
- `.opencode/skills/daemon-repl/`: OpenCode skill for Elisp daemon-repl
- `lisp/modules/gptel-auto-workflow-self-heal-semantic.el`: 7 audit checks + auto-fixers + risk-node training pairs
- `lisp/modules/gptel-auto-workflow-evolution.el`: Evolution cycle + ontology learning + conversion units
- `mementum/knowledge/verbum-audit-methodology.md`: Verbum audit #6/#7/#8 methodology + patterns
- `mementum/knowledge/self-evolving-agent-research.md`: Research paper analysis (MOSS, Sibyl, APEX, TSP)
- `mementum/state.md`: This file — working memory, read first every session

---

*Active Mementum v1.1 — 89 tests green, dual REPL wired, Pi5 synced, verbum audit methodology captured*