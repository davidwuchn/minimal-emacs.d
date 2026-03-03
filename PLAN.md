# PLAN: Native AST Tools for gptel-agent

## Status: ✓ COMPLETED

The AST tooling described in the original plan has been implemented, though under
different names and in a different file than originally planned.

## What Was Built

### Original Plan → Actual Implementation

| Planned Tool   | Actual Tool      | File                              |
| -------------- | ---------------- | --------------------------------- |
| `AST_Map`      | `Code_Map`       | `lisp/modules/gptel-tools-code.el` |
| `AST_Read`     | `Code_Inspect`   | `lisp/modules/gptel-tools-code.el` |
| `AST_Replace`  | `Code_Replace`   | `lisp/modules/gptel-tools-code.el` |
| `AST_Rename`   | *(not implemented — deemed unnecessary)* | — |

### Architecture

```
treesit-agent-tools.el (core AST engine)
    ├── treesit-agent-tools-workspace.el (workspace-wide search)
    └── gptel-tools-code.el (gptel tool registration + preview)
            ├── Code_Map     → treesit-agent-get-file-map
            ├── Code_Inspect → treesit-agent-extract-node + find-workspace
            └── Code_Replace → treesit-agent-replace-node + extract-node
```

### Key Decisions

- **Naming**: `Code_*` instead of `AST_*` — more intuitive for the LLM, avoids
  jargon. The LLM doesn't need to know it's using tree-sitter under the hood.
- **No `AST_Rename`**: The `treesit-agent-rename-symbol` backend was removed as
  dead code. Rename-symbol is better handled by language servers or search-replace.
- **Preview integration**: `Code_Replace` has a unified diff preview registered
  in `gptel--tool-preview-alist`, showing old vs new code in a side window.
- **Workspace search**: `Code_Inspect` can find definitions across project files
  via `treesit-agent-find-workspace` when the node isn't in the specified file.

## Cleanup (v0.5.6)

- Deleted `rewrite-ast-tools.el` (orphaned scratch file with dead preview fns)
- Removed `treesit-agent-rename-symbol` from `treesit-agent-tools.el`
- Updated this plan to reflect actual state
