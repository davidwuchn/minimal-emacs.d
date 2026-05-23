# ✅ evolution-next-cycle-hints Must Be a Plist

tags: plist, hints, queue-cluster-experiments, data-shape

## Symptom
`queue-cluster-experiments` in ontology-router.el pushed list entries directly onto `gptel-auto-workflow--evolution-next-cycle-hints` via `push`. This corrupted the plist structure — subsequent `plist-get` calls returned nil for everything.

## Fix
Changed to store under `:cluster-queued` key using `plist-put`. The data is now a proper plist value under a keyword key, safe for all `plist-get` consumers.

## Pattern
`evolution-next-cycle-hints` is a plist. Never push raw entries onto it. Always use `plist-put` with a keyword key. Read with `plist-get`.
