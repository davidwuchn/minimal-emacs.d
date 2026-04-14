# Troubleshooting Guide

> Common issues and solutions for nucleus/gptel agent workflows.

## Table of Contents

1. [FSM Stuck in "Typing..."](#fsm-stuck-in-typing)
2. [Task Aborted Errors](#task-aborted-errors)
3. [Malformed JSON Errors](#malformed-json-errors)
4. [Subagent Not Responding](#subagent-not-responding)
5. [Tool Call Failures](#tool-call-failures)
6. [Context Limit Issues](#context-limit-issues)
7. [Rate Limiting](#rate-limiting)

---

## FSM Stuck in "Typing..."

**Symptom:** The header-line shows "Typing..." indefinitely. You must press `C-g` to abort.

**Cause:** The FSM (Finite State Machine) failed to transition properly. Common causes:
- Network error before HTTP headers received
- JSON parsing error in streaming response
- Missing ERRS/DONE handler in agent request

**Solution:**

1. Check the FSM state:
   ```elisp
   (when (boundp 'gptel--fsm-last)
     (gptel-fsm-info gptel--fsm-last))
   ```

2. Force recovery:
   ```elisp
   M-x gptel-abort
   ```

3. Check `*Messages*` buffer for error details.

**Prevention:** Ensure `gptel-ext-fsm.el` is loaded. It adds error recovery hooks.

---

## Task Aborted Errors

**Symptom:** Subagent returns "Aborted: ... task was cancelled or timed out."

**Causes:**

| Cause | Check | Solution |
|-------|-------|----------|
| Timeout exceeded | `my/gptel-agent-task-timeout` | Increase timeout or set to `nil` |
| User cancelled | `C-g` pressed | Expected behavior |
| Parent buffer killed | Buffer no longer exists | Don't kill gptel buffers during tasks |

**Debug:**

```elisp
;; Check timeout setting
my/gptel-agent-task-timeout

;; Increase timeout (e.g., 5 minutes)
(setq my/gptel-agent-task-timeout 300)
```

---

## Malformed JSON Errors

**Symptom:** Error message "Malformed JSON in response" appears in `*Messages*`.

**Causes:**
- Backend streaming issues (common with DashScope/Qwen)
- Network interruption mid-stream
- Backend rate limiting with malformed error response

**Solutions:**

1. **Retry automatically** (handled by `gptel-ext-retry.el`):
   ```elisp
   ;; Check retry settings
   my/gptel-max-retries  ; default: 3
   ```

2. **Use non-streaming mode for subagents**:
   ```elisp
   (setq my/gptel-subagent-stream nil)
   ```

3. **Check backend-specific issues**:
   - DashScope: Add `("--http1.1" "--max-time" "100")` to backend curl options
   - Gemini: Reduce request complexity

---

## Subagent Not Responding

**Symptom:** RunAgent tool call hangs without returning.

**Debug Steps:**

1. **Check active tasks**:
   ```elisp
   (hash-table-keys gptel-agent-loop--active-tasks)
   ```

2. **Check task state**:
   ```elisp
   (when gptel-agent-loop--state
     (list
      :step-count (gptel-agent-loop--task-step-count gptel-agent-loop--state)
      :max-steps (gptel-agent-loop--task-max-steps gptel-agent-loop--state)
      :continuations (gptel-agent-loop--task-continuation-count gptel-agent-loop--state)))
   ```

3. **Check max steps limit**:
   ```elisp
   gptel-agent-loop-max-steps  ; default: 50
   gptel-agent-loop-max-continuations  ; default: 5
   ```

**Solution:**

The subagent may be hitting step/continuation limits. Check agent YAML:
```yaml
agents:
  executor:
    steps: 25  # Increase if needed
```

---

## Tool Call Failures

**Symptom:** Tool returns error or doesn't execute.

**Common Causes:**

| Error | Cause | Solution |
|-------|-------|----------|
| "Tool not found" | Tool not registered | Check `gptel--known-tools` |
| "Permission denied" | Plan mode restriction | Switch to agent mode |
| "Invalid arguments" | Tool call format wrong | Check model output |

**Debug:**

```elisp
;; List available tools
(when (boundp 'gptel--known-tools)
  (mapcar #'car gptel--known-tools))

;; Check tool in current buffer
(when (boundp 'gptel-tools)
  gptel-tools)
```

**Plan Mode Restrictions:**

In plan mode, only read-only tools are available:
- Read, Grep, Glob
- Code_Map, Code_Inspect, Diagnostics
- WebFetch, WebSearch

To use write tools (Edit, Write, Bash), switch to agent mode:
```
M-x nucleus-agent-toggle
```

---

## Context Limit Issues

**Symptom:** "context length exceeded" error from backend.

**Causes:**
- Conversation too long
- Tool results consuming too many tokens
- Image attachments in context

**Solutions:**

1. **Check context estimation**:
   ```elisp
   ;; Estimate current tokens
   (my/gptel--estimate-tokens (buffer-size))
   ```

2. **Clear context**:
   ```
   M-x gptel-clear-context
   ```

3. **Compact context automatically** (handled by `gptel-ext-retry.el`):
   - On retry, tool results are trimmed
   - Old messages may be removed

4. **Reduce file content in prompts**:
   - Don't include entire files
   - Use line ranges with Read tool

---

## Rate Limiting

**Symptom:** Frequent "429 Too Many Requests" or "Rate limit exceeded" errors.

**Provider-Specific Limits:**

| Provider | Free Tier | Paid Tier |
|----------|-----------|-----------|
| DashScope | 60 req/min | Higher |
| OpenAI | 3-500 req/min | 5000+ req/min |
| Anthropic | Varies | Check console |
| Gemini | 15 RPM | 2000 RPM |
| MiniMax | 5-hour rolling window | 10x daily quota |

**Solutions:**

1. **Enable automatic retry** (default):
   ```elisp
   ;; Already enabled via gptel-ext-retry.el
   my/gptel-max-retries  ; default: 3
   ```

2. **Backend fallback for auto-workflow** (default):
   When MiniMax hits rate limits, auto-workflow automatically fails over:
   ```
   MiniMax → DashScope → DeepSeek → CF-Gateway → Gemini
   ```
   Configure via:
   ```elisp
   gptel-auto-workflow-headless-subagent-fallbacks
   gptel-auto-workflow-executor-rate-limit-fallbacks
   ```

3. **Add delays between requests**:
   ```elisp
   (setq gptel-agent-loop-retry-delay 5.0)  ; 5 second base delay
   ```

4. **Check provider dashboard**:
   - MiniMax: https://platform.minimaxi.com/docs/token-plan/faq
   - DashScope: https://dashscope.console.aliyun.com/
   - OpenAI: https://platform.openai.com/usage
   - Anthropic: https://console.anthropic.com/

---

## Diagnostic Commands

| Command | Purpose |
|---------|---------|
| `M-x gptel-abort` | Cancel current request |
| `M-x nucleus-verify-agent-tool-contracts` | Check tool configuration |
| `M-x nucleus-tool-sanity-check` | Verify tool registration |
| `M-x gptel-clear-context` | Clear conversation context |
| `C-h v gptel--fsm-last` | Inspect FSM state |

---

## Getting Help

1. Check `*Messages*` buffer for detailed error logs
2. Enable verbose logging:
   ```elisp
   (setq nucleus-tools-verbose t)
   (setq gptel-log-level 'debug)
   ```
3. Review the [MODULE_ARCHITECTURE.md](MODULE_ARCHITECTURE.md) for system overview