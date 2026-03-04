# STATE: Current Emacs Project Configuration

> Last updated: 2026-03-04 (tag v0.5.15)

## Architecture Overview

Custom gptel + nucleus Emacs configuration. gptel provides the LLM chat/FSM engine; nucleus layers on tool management, agent presets, prompts, and UI.

### Module Structure (`lisp/modules/`)

| Module | Purpose | Lines |
|--------|---------|-------|
| `gptel-ext-core.el` | Core advice/hooks: retry, FSM recovery, streaming, tool sanitization, progressive trimming, pre-send compaction | ~1790 |
| `gptel-ext-backends.el` | Backend configuration (Moonshot, DashScope, DeepSeek, Gemini, OpenRouter, etc.) | ~111 |
| `gptel-ext-context.el` | Context management extensions | |
| `gptel-ext-learning.el` | Learning integration: auto-evolve instinct files on git commit via `git-commit-finish-hook` | ~144 |
| `gptel-ext-security.el` | ACL router advice on gptel-make-tool | ~110 |
| `gptel-tools.el` | Tool registration orchestrator, readonly/action tool lists | ~320 |
| `gptel-tools-agent.el` | RunAgent tool + subagent delegation + upstream Agent deregistration | ~326 |
| `gptel-tools-apply.el` | ApplyPatch tool | |
| `gptel-tools-bash.el` | Async Bash tool | |
| `gptel-tools-code.el` | Code_Map, Code_Inspect, Code_Replace, Diagnostics, Code_Usages | ~460 |
| `gptel-tools-edit.el` | Async Edit tool | |
| `gptel-tools-glob.el` | Async Glob tool | |
| `gptel-tools-grep.el` | Async Grep tool | |
| `gptel-tools-introspection.el` | Emacs introspection tools (describe_symbol, get_symbol_source, find_buffers_and_recent) | |
| `gptel-tools-preview.el` | Unified Preview tool (diff display in side window) | ~290 |
| `nucleus-analytics.el` | Usage analytics | |
| `nucleus-mode-switch.el` | Plan/Agent mode switching | |
| `nucleus-presets.el` | Preset management, agent patching, tool contract validation | ~360 |
| `nucleus-prompts.el` | Prompt loading from assistant/prompts/ | ~280 |
| `nucleus-tools.el` | Toolset definitions (nucleus-toolsets constant), tool filtering | ~600 |
| `nucleus-tools-validate.el` | Tool signature validation (M-x nucleus-validate-tool-signatures) | |
| `nucleus-tools-verify.el` | Tool registration verification (M-x nucleus-verify-tools-interactively) | |
| `nucleus-ui.el` | Header-line, UI helpers | ~100 |

### Confirmation UI (`lisp/gptel-tool-ui.el`)

3 tiers mapping to upstream `gptel-confirm-tool-calls`:

| Level | Upstream value | Behavior |
|-------|---------------|----------|
| `auto` | `nil` | No confirmation ever |
| `normal` | `'auto` | Confirm tools with `:confirm t` (default) |
| `confirm-all` | `t` | Confirm every tool call |

Minibuffer dispatch: `y/n/k/a/i/p/q`. Upstream `n` = "defer" (FSM stays paused, overlay stays active — intentional upstream behavior).

### Toolsets (`nucleus-toolsets`)

| Set | Tools | Used by |
|-----|-------|---------|
| `:readonly` | 18 | Plan mode, introspector subagent |
| `:researcher` | 19 | Researcher subagent |
| `:nucleus` | 30 | Agent mode, executor subagent |
| `:explorer` | 3 | Explorer subagent (Glob/Grep/Read) |
| `:reviewer` | 3 | Reviewer subagent (Glob/Grep/Read) |
| `:snippets` | (= `:nucleus`) | Derived from `:nucleus`; tools with supplemental prompts |

### Advice/Hook Chain

| Advice | Target | Type | File | Purpose |
|--------|--------|------|------|---------|
| `my/gptel--sanitize-tool-calls` | `gptel--handle-tool-use` | `:before` | gptel-ext-core.el | Pre-filter nil tool calls |
| `my/gptel--detect-doom-loop` | `gptel--handle-tool-use` | `:before` | gptel-ext-core.el | Abort repeated identical tool calls |
| `my/gptel--display-tool-calls` | `gptel--display-tool-calls` | `:override` | gptel-ext-core.el | Enhanced tool confirmation UI |
| `my/gptel-auto-retry` | `gptel--fsm-transition` | `:around` | gptel-ext-core.el | Exponential backoff retry |
| `my/gptel--compact-payload` | `gptel-curl-get-response` | `:before` | gptel-ext-core.el | Pre-send payload compaction |
| `my/gptel-fix-fsm-stuck-in-type` | `gptel-curl--stream-cleanup` | `:around` | gptel-ext-core.el | Unstick FSM from TYPE state |
| `my/gptel--stream-set-flag` | `gptel-curl--stream-insert-response` | `:before` | gptel-ext-core.el | Set streaming flag for jit-lock protection |
| `my/gptel--jit-lock-safe` | `jit-lock-function` | `:around` | gptel-ext-core.el | Suppress jit-lock errors in gptel-mode buffers |
| `my/gptel-agent--task-override` | `gptel-agent--task` | `:override` | gptel-tools-agent.el | Parent-buffer tracking, large-result truncation |
| `my/gptel--deregister-upstream-agent` | `gptel-agent-update` | `:after` | gptel-tools-agent.el | Remove upstream "Agent" tool (RunAgent is superior) |

### Payload Management Architecture

Three-layer defense against oversized API payloads:

```
Layer 1 — Pre-send (retries=0): my/gptel--compact-payload
  → Estimates JSON bytes via gptel--json-encode
  → 4-pass trimming if over limit: tool results → reasoning → tools array → aggressive

Layer 2 — Retry (retries=1): my/gptel-auto-retry
  → Trim tool results (keep count decreasing with retries)

Layer 3 — Retry (retries=2+): my/gptel-auto-retry
  → Truncate ALL results + strip reasoning_content + reduce tools array
```

Key functions in `gptel-ext-core.el`:
- Lines 1119-1136: Retry defcustoms (`my/gptel-max-retries`, etc.)
- Lines 1138-1185: `my/gptel--trim-tool-results-for-retry`
- Lines 1187-1205: `my/gptel--trim-reasoning-content`
- Lines 1207-1260: `my/gptel--reduce-tools-for-retry`
- Lines 1262-1352: `my/gptel-auto-retry` (exponential backoff + progressive trimming)
- Lines 1356-1470: `my/gptel--compact-payload` (pre-send estimation + 4-pass trim)

### Code Tools Pipeline

```
treesit-agent-tools.el (core AST engine)
    ├── treesit-agent-tools-workspace.el (workspace-wide search)
    └── gptel-tools-code.el (gptel tool registration + preview)
            ├── Code_Map     (file structure via get-file-map)
            ├── Code_Inspect (node extraction via extract-node + find-workspace)
            ├── Code_Replace (structural editing via replace-node)
            ├── Code_Usages  (references via LSP/ripgrep cascade)
            └── Diagnostics  (project-wide via flymake/LSP/CLI linters)
```

### Upstream gptel

Version 0.9.9.4 installed, but `.elc` files contain a **newer unreleased version** with the full FSM architecture (`gptel-fsm` struct). The `.el` source files are stale and don't match the compiled bytecode. DO NOT edit upstream files under `var/elpa/`.

## Active Backend

Default: `gptel--moonshot` / `kimi-k2.5` (`api.kimi.com`). Single source of truth in `gptel-config.el` lines 35-36. Switched from DashScope — better tool-calling reliability and streaming stability. DashScope, DeepSeek, Gemini, OpenRouter, Copilot, MiniMax, and CF-Gateway remain defined in `gptel-ext-backends.el` as available alternatives.

DeepSeek (`gptel--deepseek`) is available with `deepseek-chat` (V3) and `deepseek-reasoner` (R1). Considered for routing plan-mode queries to DeepSeek reasoner, but deferred — single backend is simpler to debug and Moonshot handles all modes well.

## Known Issues

None currently. All identified bugs have been fixed and committed.

## Feature Evaluation Decisions (v0.5.14)

Evaluated OpenCode/Roo Code/Cursor-style features for applicability to nucleus. Decisions:

| Feature | Decision | Rationale |
|---------|----------|-----------|
| Three-layer defense (tool-level + history pruning + LLM compaction) | **Skip** | Already covered by our 3-layer retry/compaction system |
| ECA-style recovery (proactive 75% + reactive overflow) | **Skip** | Pre-send compaction + retry trimming already covers this |
| Explicit provider error classification | **Skip for now** | Single backend (Moonshot); retry handles main failure mode. Revisit if misclassified errors appear |
| Per-mode model routing (Roo-style 7 modes) | **Skip** | K2.5 handles all modes; per-preset model overrides already architecturally supported if needed later |
| @-mention context selection | **Skip** | gptel-context + nucleus tools already provide this; agent can pull its own context via tools |
| Prompt caching (explicit cache headers) | **Skip** | OpenAI-compatible backends do server-side caching automatically; no client changes needed |
| Compaction agent (LLM summarization) | **Skip** | Rare edge case for very long sessions; complexity not justified |
| Per-tool output limits | **Skip** | Flat 4000-char truncation on subagents works fine |

### Recent Changes (v0.5.15)

- **Fix gptel-ext-learning.el** (⊘): Cleaned 18 unnecessary requires (backends, gptel-openai, etc.) → only `cl-lib`, `seq`, `subr-x`. Fixed instinct path (hardcoded `instincts/` → `my/learning-instincts-dirs` defcustom pointing to `~/.config/opencode/skill/continuous-learning/instincts`). Fixed frontmatter regex (PCRE `[\s\S]*?` → Emacs `\(?:.*\n\)*?`). Fixed slug extraction (`###` → `##`). Added proper `my/learning--parse-frontmatter` parser. Unicode regex fix: `[a-zA-Z_-]` → `[[:alpha:]_-]` for parsing Greek letter keys like `φ` in instinct frontmatter.
- **Docs update** (◈): STATE.md Active Backend section, Feature Evaluation Decisions table, Payload Management Architecture diagram. LEARNING.md "Feature Evaluation Discipline" section. INTRO.md freshened.
- **Test suite**: 26 inline tests (5 groups) for learning module: frontmatter parsing (real + synthetic), slug extraction, update-instinct, learning-ref traceability, auto-evolve integration. All pass.

### Recent Changes (v0.5.14)

- **Pre-send payload compaction** (⚒): New `my/gptel--compact-payload` advice on `gptel-curl-get-response` estimates JSON payload byte size before the first send. If over `my/gptel-payload-byte-limit` (default 200KB) or model-specific limit, proactively applies 4-pass progressive trimming (tool results → reasoning → tools array → aggressive trim) to prevent wasted retries. Model limits in `my/gptel-model-context-bytes` alist.
- **ERT test suite expanded** (51 tests): 13 new tests for pre-send compaction covering byte estimation, effective limit resolution, compaction passes, disabled/retry skip scenarios.

### Recent Changes (v0.5.13)

- **Centralize backend/model config** (⚒): Single source of truth in `gptel-config.el` lines 35-36. `nucleus-presets.el` agent/plan presets now derive from `gptel-backend`/`gptel-model`. `gptel-tools-agent.el` subagent backend/model defcustoms default to nil (inherit global). Switching providers requires changing exactly one line.
- **Tools array reduction on retry** (⚒): New `my/gptel--reduce-tools-for-retry` function filters `:data :tools` and `:tools` struct list to only tools actually called in the conversation history. Activated on retry 2+ (alongside reasoning stripping). Removes ~60-80% of tool definitions (~5-8KB) from conversations that use only 3-5 of 18+ registered tools.

### Recent Changes (v0.5.12)

- **Progressive payload trimming** (⊘): `my/gptel--trim-tool-results-for-retry` now escalates trimming with each retry: keep count = `max(0, default - retries)`. Retry 1 keeps 1 recent tool result (was 2), retry 2+ keeps 0 (truncates ALL). New `my/gptel--trim-reasoning-content` function strips `reasoning_content` fields from assistant messages on retry 2+. This addresses DashScope connection resets on oversized payloads after multiple tool-use rounds.
- **ERT test suite** (24 tests → 51 tests): `tests/test-gptel-trim.el` covers progressive trimming behavior, reasoning stripping, tools reduction, pre-send compaction, edge cases, and integration scenarios.

### Recent Changes (v0.5.10-v0.5.11)

- **Tool-result trimming on retry** (v0.5.10): Initial implementation of `my/gptel--trim-tool-results-for-retry` — truncates old tool results on retry, keeping most recent 2 intact.
- **Paredit M-: RET fix** (v0.5.11): Fixed `eval-expression` minibuffer where RET inserted newline instead of confirming, using `minor-mode-overriding-map-alist`.

- **Symlink cleanup & data directory consolidation**: Removed root-level `elpa/` and `tree-sitter/` symlinks that pointed into `var/`. These were unnecessary (paths already configured in `pre-early-init.el` and `post-early-init.el`) and created a symlink footgun risk (`rm -rf symlink/` follows the link and deletes target contents).
- **`.gitignore` allowlist fix**: Added `!pre-early-init.el` and `!post-early-init.el` to the deny-all allowlist — these were tracked via `git add -f` but not explicitly allowlisted.
- **Full package recovery**: After accidental data loss from `rm -rf` following symlinks, reinstalled all 99 ELPA packages + eca (via `package-vc-install`) and recompiled all 8 tree-sitter grammars (ABI 14, elisp ABI 13).

### Recent Changes (v0.5.8)

- **Trim custom.el** (859bb4b): Reduced `package-selected-packages` to just `(eca)` — all other packages are declared in config files and installed via `package-install` on demand.
- **Dead code cleanup** (e81886e): Removed unused `:core` toolset, derived `:snippets` from `:nucleus`, deleted `nucleus-register-tool` helper, removed dead `gptel-tools.el` variables. Added `:depth` to advice ordering.
- **jit-lock timing gap fix** (de8e1b5): Changed `my/gptel--jit-lock-safe` gate from `my/gptel--streaming-p` to `(bound-and-true-p gptel-mode)` — eliminates post-response refontification gap.
- **INTRO.md** (255d4af): Fork overview and nucleus architecture summary for GitHub.
- **Unified nucleus engage header** (86fb489): All 28 agent/prompt/skill/doc files now use canonical `[phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`. Collaboration lines preserved per-file (`Human ⊗ AI`, `Human ∧ AI` for nucleus-tutor, `Human ⊗ AI ⊗ REPL` for clojure-expert and reference docs).
- **Restore upstream init.el**: Reverted `init.el` to exact upstream `jamescherti/minimal-emacs.d`, deleted redundant `lisp/init-defaults.el`. All customizations now live exclusively in `post-init.el` / `post-early-init.el` / `pre-early-init.el` as intended. Added missing `no-byte-compile: t` to `post-early-init.el`.

### Phantom Issues (DO NOT attempt to fix)

These were hallucinated by prior AI sessions — verified as non-issues:

- `my/gptel--deliver-subagent-result` "truncation risk" — the 4000 char truncation IS the fix
