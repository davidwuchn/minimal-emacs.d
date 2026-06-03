# Core Patterns in gptel-benchmark-subagent.el

## Subagent Dispatch Core Pattern
`gptel-benchmark-call-subagent` is the central routing function (~250 lines). Multi-phase provider selection:
1. Ontology category → best-model from ai-behaviors
2. Headless fallback chain → skip rate-limited providers
3. Preset/global defaults → override-preset or gptel-agent-preset
4. Model bump (≥5 consecutive failures → escalate)

Key patterns verified in early-exploration:
- `gptel-benchmark--plist-delete-all`: O(n) with nconc (was O(n²) with append)
- `effective-effort` variable: eliminated unused-var warning by wrapping cost recording + effort-param in nested let forms
- declare-function stubs added for `gptel-auto-workflow--subagent-persona` and `my/gptel--sanitize-for-logging`
- Docstrings fixed to ≤80 chars (removed 4 byte-compile warnings)
- Structured ASSUMPTION/BEHAVIOR/EDGE/TEST comments added for core dispatch
