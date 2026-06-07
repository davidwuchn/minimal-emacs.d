# nucleus tools

## Purpose

Canonical tool definitions and validation for the nucleus gptel-agent presets.
Provides marker-based tool classification (can-edit, can-read, symbolic, web,
memory, delegates, etc.) enabling trait-based toolset derivation instead of
hardcoded name lists. Includes JSON Schema-like argument validation at runtime
(string patterns, numeric bounds, array size limits), progressive result
shortening, per-project tool exclusions, tool sanity checking, preset-to-toolset
syncing, and agent tool contract enforcement.

## File Stats

- **Lines**: 893
- **Path**: `lisp/modules/nucleus-tools.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `nucleus-tools-with-marker` | 91 | Return tools carrying a specific marker |
| `nucleus-tool-has-marker-p` | 95 | Check if tool carries a specific marker |
| `nucleus-tools-with-any-marker` | 99 | Return tools with any of given markers (union) |
| `nucleus-toolset-from-markers` | 110 | Derive toolset from include/exclude markers |
| `nucleus-limit-result-length` | 137 | Progressive result shortening with factory fallbacks |
| `nucleus-active-markers` | 201 | Return markers with at least one active tool |
| `nucleus-marker-available-p` | 214 | Check if marker has active tools |
| `nucleus-get-tools` | 351 | Return tool list for a set-name, filtering unregistered |
| `nucleus-tool-sanity-check` | 392 | Check if gptel-tools match expected tools for preset |
| `nucleus-sync-tool-profile` | 445 | Sync gptel-tools to match active preset |
| `nucleus-tools--validate-contract` | 783 | Wrap function with runtime contract validation |
| `nucleus-tools--advise-make-tool` | 849 | Advice on gptel-make-tool for contract enforcement |
| `nucleus-tools-setup` | 870 | Module setup: hooks, advice, cache invalidation |

## Tool Markers

| Marker | Purpose |
|--------|---------|
| `:can-edit` | Tool modifies files or system state |
| `:can-read` | Tool reads/queries without side effects |
| `:symbolic` | Tool operates at symbol/code-structure level |
| `:web` | Tool accesses external web resources |
| `:memory` | Tool reads/writes persistent memory (mementum) |
| `:delegates` | Tool delegates to sub-agents |
| `:requires-project` | Tool needs an active project context |
| `:plan-excluded` | Tool excluded from plan/readonly mode |
| `:sandbox-excluded` | Tool excluded from all sandbox profiles |
| `:file-inspector` | Tool inspects file content at granular depth |

## Toolset Definitions

| Toolset | Derivation | Purpose |
|---------|-----------|---------|
| `:readonly` | can-read - can-edit - plan-excluded | Plan mode |
| `:nucleus` | can-read + can-edit | Full action |
| `:executor` | can-read + can-edit - delegates | Action without delegation |
| `:researcher` | Hand-curated | Codebase + web research |
| `:explorer` | Hand-curated | Codebase exploration |
| `:reviewer` | Hand-curated | Code review |
| `:analyzer` | Hand-curated | Benchmark analysis |
| `:comparator` | Hand-curated | A/B comparison |
| `:grader` | Hand-curated | Assertion grading |

## Dependencies

- `cl-lib`, `seq`, `subr-x`

## Integration Points

- **gptel mode hook**: `nucleus-sync-tool-profile` syncs tools on mode entry
- **gptel-make-tool advice**: Contract validation at depth 20 (innermost, after security ACL at depth 10)
- **ext-security**: Uses `nucleus-tool-has-marker-p` for workspace boundary checks
- **gptel-sandbox**: Uses `nucleus-tool-markers` for profile derivation and tool classification
- **Agent presets**: `nucleus-agent-tool-contracts` maps agent names to toolsets

## See Also

- [ext security](gptel-ext-security.md)
- [sandbox](gptel-sandbox.md)
- [tools agent base](gptel-tools-agent-base.md)