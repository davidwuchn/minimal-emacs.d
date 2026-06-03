# Allium Input Validation Pattern

All three Allium v3 functions (`allium-distill`, `allium-check`, `allium-decompile`) now have input validation guards:

1. **Availability check**: gptel-request + functionp callback
2. **Type check**: null or non-string → skip
3. **Whitespace check**: whitespace-only → treated as empty
4. **Length check**: <10 chars (check/decompile) or <20 chars (distill) → skip
5. **Structure check** (check/decompile only): `:states` or `:initial` marker required

All guards call `callback(nil)` and return nil to maintain the callback contract.
All guards emit `[allium]` messages for traceability.

Files: `gptel-tools-agent-prompt-build.el` (functions 385-465)