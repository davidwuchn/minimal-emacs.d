---
name: retry-first-subscription-backends
created: 2026-05-12
tags: [retry, executor, fallback, subscription, minimax]
---

# Retry-First Pattern for Subscription Backends

Monthly subscription backends (MiniMax) should retry more aggressively before advancing to fallback.

**Problem:** Executor only checked `should-blacklist-provider-p` (rate limits), missing timeouts (curl 28). Advanced too quickly.

**Solution:** Track `provider-attempts`, only advance after N consecutive failures:
- `max-per-provider-attempts = 5` (was 2)
- `max-retries = 5` (was 2)

**Distinction:**
- Timeout → retry 5×, advance WITHOUT blacklisting
- Rate limit/hard quota → retry 5×, advance AND blacklist

Same pattern as aux subagents in `gptel-tools-agent-benchmark.el:555-584`.

**Files:**
- `gptel-tools-agent-error.el:500-580`: Executor retry loop
- `gptel-tools-agent-prompt-build.el:893-910`: Retry limits