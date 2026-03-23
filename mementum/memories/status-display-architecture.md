# Status Display Architecture

## Insight

gptel uses a two-layer status display system:

| Layer | Mechanism | Scope | Content |
|-------|-----------|-------|---------|
| Main LLM | `header-line-format` | Buffer-wide | Top-level request status |
| Sub-agent | In-buffer overlays | Task-local | Sub-agent specific status |

## Main LLM (Header-line)

**Function:** `gptel--update-status` (`gptel.el:992-1009`)

```elisp
(defun gptel--update-status (&optional msg face)
  (when gptel-mode
    (if gptel-use-header-line
        (setf (nth 1 header-line-format) ...)
      ...)))
```

**States shown:** "Typing...", "Waiting...", "Ready", "Error", "Calling tool...", "Calling Agent..."

**Handlers:** `gptel-send--handlers` includes:
- `gptel--update-wait` → " Waiting..."
- `gptel--update-tool-call` → " Calling tool..."

## Sub-agent (Overlays)

**Function:** `gptel-agent--task-overlay` (`gptel-agent-tools.el:1300-1324`)

Creates overlay with `'after-string` showing:
- Task description
- "Waiting..." / "Calling Tools..."
- Tool call count

**Handlers:** `gptel-agent-request--handlers` (separate from main):
- `gptel-agent--indicate-wait` → updates overlay
- `gptel-agent--indicate-tool-call` → updates overlay

## Why Two Layers?

1. **Header-line** = single source of truth for buffer state
2. **Overlays** = parallel, non-conflicting sub-agent status
3. **Both can show simultaneously** without confusion

## Local Code Alignment

Our code correctly calls `gptel--update-status` when launching sub-agents:

```elisp
;; gptel-tools-agent.el:194
(gptel--update-status " Calling Agent..." 'font-lock-escape-face)
```

This is intentional — the main buffer IS waiting for the sub-agent.

## Pattern

```
λ status(x).    main_llm(x) → header_line
                | sub_agent(x) → in_buffer_overlay
                | both(x) → parallel_layers
```

## Related

- `gptel.el:992-1009` — `gptel--update-status`
- `gptel-agent-tools.el:1300-1324` — `gptel-agent--task-overlay`
- `gptel-agent-tools.el:1256-1298` — indicate functions

## Captured

2026-03-23 — Architecture verification for header-line vs overlays