# ✅ JSON Deserialization Must Set json-key-type

tags: JSON, json-read, json-key-type, keyword, plist, cross-subsystem-state

## Symptom
`restore-next-cycle-hints` read `cross-subsystem-state.json` with `json-read` but didn't set `json-key-type 'keyword`. The JSON keys were read as strings ("category-budget") but code used `plist-get` with keywords (:category-budget) → always nil. Cross-cycle state restoration was dead.

## Fix
Set `json-object-type 'plist`, `json-array-type 'list`, `json-key-type 'keyword` in the `let` binding around `json-read`. Matches the serialization format used by `persist-next-cycle-hints`.

## Pattern
Any `json-read` that will be consumed with `plist-get` MUST set `json-key-type 'keyword`. Check `update-controller-from-champion-changes` for correct example.
