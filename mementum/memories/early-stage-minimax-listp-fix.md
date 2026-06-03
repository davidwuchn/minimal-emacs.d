## MiniMax `listp` Serialization Error - Analysis

**Error**: `Wrong type argument: listp, "qwen3.6-plus"` — backend name string passed where list expected.

**Root cause**: `gptel-backend-name` returns a string for MiniMax backend, but caller expects a list. The model name string `"qwen3.6-plus"` gets passed to a function requiring a list.

**Fix needed**: Add `Wrong type argument: listp,` to `gptel-auto-experiment--error-categories` as `:api-error` category so it triggers provider failover. Also add to `gptel-auto-experiment--should-blacklist-provider-p` as a systematic failure (not transient).

**Location**: `lisp/modules/gptel-tools-agent-error.el` line ~697-740

**Impact**: Without this fix, MiniMax systematic failure doesn't trigger failover → all experiments on MiniMax fail silently → pipeline stalls.