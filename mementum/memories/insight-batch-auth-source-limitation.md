# Batch Mode Auth-Source Limitation

**Discovery:** `gptel-auto-workflow--backend-available-p` returns nil for all backends when run via `emacs -Q --batch`.

**Root Cause:** `my/gptel-api-key` uses auth-source to retrieve API keys. In batch mode (`-Q`), auth-source is not initialized with the user's credentials file, so all key lookups fail.

**Implication:** Provider availability checks MUST be done in the live daemon context, not batch mode. The daemon (PID 3008726) has full auth-source initialization and can properly check provider availability.

**Pattern:**
```
batch-check(x) → auth-source nil → all unavailable
daemon-check(x) → auth-source ready → accurate availability
```

**Lesson:** Don't rely on batch-mode provider checks. Use daemon introspection or live status instead.

**Date:** 2026-05-08
