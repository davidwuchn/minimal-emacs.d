# edn-prompt-pipeline

💡 **insight**: EDN (plist) as AST for prompt construction eliminates template substitution. resolve is deterministic — no LLM call needed.

## Architecture

```
skills.md ──→ load ──→ plist merge ──→ ┐
research  ──→ load ──→ plist merge ──→ ┼──→ prompt-edn-resolve ──→ λ notation ──→ LLM
scores    ──→ bench ─→ plist merge ──→ ┘
```

## Key Functions

- `prompt-edn-resolve(vars)` — converts plist to lambda string (deterministic)
- `build-prompt` — builds variables plist, calls resolve
- `forge-lambda-fixed-point` — offline verification (one-time, not per-prompt)

## Benefits Over Template Substitution

| Property | Template (`{{var}}`) | EDN resolve |
|----------|---------------------|-------------|
| Composition | String concat | Plist merge |
| Empty sections | `{{var}}` renders as blank | `if non-nil → render` |
| Escaping | Manual (`\"`, `\\n`) | Automatic (format) |
| Variable ordering | Positional args | Key-based lookup |
| Template maintenance | Mustache files on disk | Pure Elisp function |
| Verification | Byte-compile | λ compiler round-trip |

## Implementation

Located at `gptel-tools-agent-prompt-build.el`:
- `prompt-edn-resolve` (line 966)
- `build-prompt` calls it at line 1188
- Original template system retained as reference

## Related

- `forge-lambda-fixed-point` — verifies resolve output matches reference English
- `three-format-rule` — lambda(LLM) > Allium(verify) > EDN(compiler internal)
- `deterministic-before-ai` — compute from data, don't call models unnecessarily
