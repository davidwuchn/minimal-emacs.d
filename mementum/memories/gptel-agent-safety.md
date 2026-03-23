# gptel-Agent Safety Mechanisms: Reuse vs Local

## Insight

We reuse gptel-agent's confirmation and timeout mechanisms directly. Local extensions add project-specific limits and defensive patterns not in upstream.

## What We Reuse from gptel-Agent

### 1. Tool Confirmation (`:confirm t`)

**Mechanism:** Tool property requiring user approval before execution.

**Tools with confirmation:**

| Tool | Why Confirmed |
|------|---------------|
| Bash | Arbitrary command execution |
| Eval | Arbitrary code execution |
| Mkdir | Creates directories |
| Edit | Modifies files |
| Insert | Modifies files |
| Write | Creates/overwrites files |
| Agent | Launches sub-agent |

**Status:** ✅ Directly using gptel-agent tools with `:confirm t`.

### 2. Confirmation UI (`gptel-agent--confirm-overlay`)

**Mechanism:** Overlay preview showing tool call before execution.

**Keybindings:**
- `n` / `p` — Navigate between tool calls
- `q` — Reject tool call
- `TAB` — Expand/collapse details

**Status:** ✅ UI provided by gptel-agent, no local changes needed.

### 3. Web Timeouts (`gptel-agent--fetch-with-timeout`)

**Mechanism:** 30-second timeout for WebSearch/WebFetch requests.

**Implementation:** 
```elisp
(let ((timeout 30) timer done ...)
  (run-at-time timeout nil ...))
```

**Status:** ✅ Built into gptel-agent, automatically applied.

---

## What We Added Locally

### 1. Max Steps Limit (`gptel-agent-loop-max-steps`)

**Purpose:** Prevent runaway agent loops.

**Default:** 50 steps

**Location:** `lisp/modules/gptel-agent-loop.el`

**Code:**
```elisp
(defcustom gptel-agent-loop-max-steps 50
  "Maximum number of tool calls before forcing DONE state.")
```

**Why local:** Project-specific limit, upstream has no equivalent.

### 2. Doom-Loop Detection

**Purpose:** Detect 3+ identical consecutive tool calls and abort.

**Trigger:** Same tool + same args called 3+ times in a row.

**Action:** Abort with error message.

**Location:** `lisp/modules/gptel-ext-tool-sanitize.el`

**Why local:** Defensive pattern, not in upstream.

### 3. Immutable File Protection

**Purpose:** Protect critical files from AI modification.

**Status:** ⚠️ **NOT YET IMPLEMENTED** (Gap #10)

**Planned:**
- `constraints.md` defining immutable/modifiable files
- `my/gptel-can-modify-p` function
- Hook into Write/Edit/Insert tools

### 4. Payload Size Limits

**Purpose:** Prevent oversized edits from corrupting files.

**Implementation:**
```elisp
(defcustom gptel-tools-preview-max-replacement-size 1000000
  "Maximum size in bytes for replacement content (default 1MB).")
```

**Location:** `lisp/modules/gptel-tools-preview.el`

**Why local:** Project-specific threshold.

---

## Decision Matrix

| Feature | Upstream | Local | Why |
|---------|----------|-------|-----|
| `:confirm t` | ✅ | — | Upstream mechanism |
| Confirmation UI | ✅ | — | Upstream provides |
| Web timeout (30s) | ✅ | — | Upstream provides |
| Max steps limit | ❌ | ✅ | Project-specific |
| Doom-loop detection | ❌ | ✅ | Defensive pattern |
| Immutable file protection | ❌ | ⚠️ Planned | Project-specific |
| Payload size limits | ❌ | ✅ | Project-specific |

---

## Lambda

```
λ safety(x).    upstream_has(x) → reuse(x)
                | project_specific(x) ∨ defensive(x) → local(x)
                | confirm(t) ∧ timeout(x) → upstream
                | limit(x) ∧ threshold(x) → local
```

---

## Upstream PR Candidates

| Feature | Value | Complexity | Recommendation |
|---------|-------|------------|----------------|
| Max steps as tool property | High | Low (~10 lines) | Consider PR |
| Payload size limit | Medium | Low (~5 lines) | Consider PR |
| Doom-loop detection | Medium | Low (~20 lines) | Keep local (opinionated) |
| Immutable file protection | High | Medium | Keep local (config-heavy) |

---

## Files Reference

| File | Purpose |
|------|---------|
| `var/elpa/gptel-agent/gptel-agent-tools.el` | Upstream tools with `:confirm t` |
| `lisp/modules/gptel-agent-loop.el` | Max steps, hard loop |
| `lisp/modules/gptel-ext-tool-sanitize.el` | Doom-loop detection |
| `lisp/modules/gptel-tools-preview.el` | Payload size limits |
| `lisp/modules/gptel-ext-tool-permits.el` | Granular allow/deny |
| `lisp/modules/gptel-ext-security.el` | Path validation |

---

## Captured

2026-03-23 — Analysis of gptel-agent safety mechanisms during OUROBOROS gap resolution.