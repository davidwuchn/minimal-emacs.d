---
title: plist-put Return Value Bug Class
date: 2026-05-16
symbol: ❌
---

# plist-put Return Value Bug Class

`plist-put` has a silent trap: it mutates in-place when the key already exists but returns a **new plist** when the key is new. Discarding the return value silently drops new keys.

Found across 3 files, 15+ sites total:

1. **`push` on `plist-get`** (9 sites in evolution.el `consolidate-insights`): `push` creates a cons cell but `plist-get` is not a generalized variable — the cons is immediately discarded. Fix: `(setq place (plist-put place :key (cons val (plist-get place :key))))`.

2. **`plist-put` return discarded** (6 sites across strategic.el, strategic-daemon-functions.el, git.el): Pattern `(plist-put var :new-key val)` inside `when`/`unless` body. If `:new-key` doesn't exist yet, the new plist is created but never assigned back. Fix: always `(setq var (plist-put var :key val))`.

3. **For hash-table values**: Must also `(puthash key var table)` after `setq` to persist the updated plist back into the hash table.

Detection: `rg 'plist-put\s+\w' --glob '*.el' | rg -v setq` catches most instances. Audit any result that isn't preceded by `setq`.
