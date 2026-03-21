# Performance Tuning Guide

> Optimize nucleus/gptel for your workflow and hardware.

## Table of Contents

1. [Cache Configuration](#cache-configuration)
2. [Agent Loop Settings](#agent-loop-settings)
3. [Retry Configuration](#retry-configuration)
4. [Context Management](#context-management)
5. [Streaming vs Non-Streaming](#streaming-vs-non-streaming)
6. [Tool Execution](#tool-execution)
7. [Provider-Specific Tuning](#provider-specific-tuning)

---

## Cache Configuration

### Subagent Result Cache

Subagent results are cached to avoid redundant LLM calls.

```elisp
;; Cache TTL in seconds (default: 5 minutes)
(setq my/gptel-subagent-cache-ttl 300)

;; Disable caching
(setq my/gptel-subagent-cache-ttl 0)
```

**Recommendations:**

| Use Case | TTL | Reason |
|----------|-----|--------|
| Development | 60-300 | Rapid iteration |
| Research | 600-1800 | Stable queries |
| Production | 300-900 | Balance freshness/speed |

**Cache Statistics:**

```elisp
;; Check cache size
(hash-table-count my/gptel--subagent-cache)

;; Clear cache
(M-x my/gptel--subagent-cache-clear)
```

### Context Window Cache

Model context windows are cached for token estimation.

```elisp
;; Default context window fallback (tokens)
(setq my/gptel-default-context-window 128000)

;; Auto-refresh interval (days)
(setq my/gptel-context-window-auto-refresh-interval-days 7)
```

---

## Agent Loop Settings

### Maximum Steps

Controls how many tool calls a subagent can make.

```elisp
;; Default maximum tool calls
(setq gptel-agent-loop-max-steps 50)

;; Per-agent configuration (in YAML)
agents:
  executor:
    steps: 25
  reviewer:
    steps: 15
  explorer:
    steps: 10
```

**Trade-offs:**

| Setting | Pros | Cons |
|---------|------|------|
| Low (10-20) | Faster completion, less cost | May not finish complex tasks |
| Medium (25-50) | Balanced | Good for most tasks |
| High (75-100) | Handles complex tasks | Higher cost, may loop |

### Continuation Limits

Controls how many times the agent auto-continues.

```elisp
;; Maximum auto-continuations
(setq gptel-agent-loop-max-continuations 5)
```

**What is a continuation?**

When the model outputs planning text without tool calls, a continuation prompt is injected to force tool usage. This prevents infinite loops.

**Symptoms of too low:**
- Agent stops with "[RUNAGENT_INCOMPLETE]" marker
- Tasks not fully completed

**Symptoms of too high:**
- Excessive API calls
- Higher costs

### Hard Loop Mode

Controls whether the agent automatically continues.

```elisp
;; Auto-continue incomplete tasks (default)
(setq gptel-agent-loop-hard-loop t)

;; Stop after each turn, require user input
(setq gptel-agent-loop-hard-loop nil)
```

---

## Retry Configuration

### Retry Settings

```elisp
;; Maximum retry attempts
(setq my/gptel-max-retries 3)

;; Base delay between retries (exponential backoff)
;; Retries use: base * 2^attempt
;; Example: 2s -> 4s -> 8s
(setq my/gptel-retry-base-delay 2.0)
```

**When to increase:**
- Unstable network connections
- Rate-limited backends (429 errors)
- Intermittent provider outages

**When to decrease:**
- Fast fail needed for real-time applications
- Lower latency requirements

### Transient Error Detection

The system automatically retries these errors:

| Error Type | Retried |
|------------|---------|
| 429 Rate Limit | Yes |
| 500 Server Error | Yes |
| 502 Bad Gateway | Yes |
| 503 Unavailable | Yes |
| 504 Gateway Timeout | Yes |
| Malformed JSON | Yes |
| Connection timeout | Yes |
| InvalidParameter | Yes |

---

## Context Management

### Context Estimation

```elisp
;; Estimate tokens for current buffer
(my/gptel--estimate-tokens (buffer-size))

;; Get current model's context window
(my/gptel--context-window)
```

### Auto-Compaction

When context approaches the limit, automatic compaction occurs:

1. **Trim tool results** (largest consumers)
2. **Remove old messages**
3. **Strip reasoning blocks**

```elisp
;; Context usage threshold for compaction
;; Default: 0.8 (80% of context window)
(defvar my/gptel-context-compact-threshold 0.8)
```

### Manual Context Control

```elisp
;; Clear all context
M-x gptel-clear-context

;; Remove specific context items
M-x gptel-context-remove
```

---

## Streaming vs Non-Streaming

### Subagent Streaming

```elisp
;; Streaming for subagents (default: nil)
(setq my/gptel-subagent-stream nil)
```

**When to enable:**
- Long-running tasks where progress visibility matters
- Stable backends (OpenAI, Anthropic)

**When to disable:**
- DashScope/Qwen (HTTP parse errors common)
- Unstable network
- Need faster overall completion (no render overhead)

### Main Buffer Streaming

```elisp
;; Always streaming for main gptel buffer
(setq gptel-stream t)
```

---

## Tool Execution

### Parallel Tool Calls

Models may call multiple tools in parallel.

```elisp
;; Enable parallel tool calls (default)
(setq gptel-parallel-tool-calls t)

;; Disable for sequential execution
(setq gptel-parallel-tool-calls nil)
```

### Tool Result Limits

```elisp
;; Max characters for inline tool results
(setq my/gptel-subagent-result-limit 4000)

;; Larger results saved to temp files
```

### Temp File Cleanup

```elisp
;; Auto-delete temp files after N seconds
(setq my/gptel-subagent-temp-file-ttl 300)

;; Disable auto-cleanup
(setq my/gptel-subagent-temp-file-ttl 0)
```

---

## Provider-Specific Tuning

### DashScope (Qwen, GLM)

```elisp
;; Backend curl options for stability
(setq gptel-curl-default-args
      '("--http1.1" "--max-time" "100"))

;; Use non-streaming for subagents
(setq my/gptel-subagent-stream nil)

;; Higher retry count for rate limits
(setq my/gptel-max-retries 5)
```

### OpenAI

```elisp
;; Standard configuration works well
(setq my/gptel-max-retries 3)
(setq my/gptel-subagent-stream t)  ; Streaming OK
```

### Anthropic

```elisp
;; Streaming stable
(setq my/gptel-subagent-stream t)

;; Prompt caching for long contexts
;; (handled automatically by gptel)
```

### Gemini

```elisp
;; Gemini has 1M context - use it
(setq my/gptel-default-context-window 1048576)

;; May need lower timeouts
(setq my/gptel-agent-task-timeout 120)
```

---

## Benchmarking

### Run Performance Tests

```elisp
;; Run skill benchmark
M-x gptel-benchmark-run-skill

;; View results
M-x gptel-benchmark-show-results
```

### Key Metrics

| Metric | Target | Threshold |
|--------|--------|-----------|
| Step count | 5-15 | > 25 = overgrowth |
| Duration | 30-60s | > 120s = slow |
| Continuations | 1-2 | > 5 = loop risk |
| Tool success | > 95% | < 90% = investigate |

---

## Quick Reference

| Setting | Default | Recommended Range |
|---------|---------|-------------------|
| `my/gptel-subagent-cache-ttl` | 300 | 60-1800 |
| `gptel-agent-loop-max-steps` | 50 | 15-100 |
| `gptel-agent-loop-max-continuations` | 5 | 3-10 |
| `my/gptel-max-retries` | 3 | 2-5 |
| `my/gptel-subagent-result-limit` | 4000 | 2000-8000 |
| `my/gptel-subagent-temp-file-ttl` | 300 | 0-600 |