# Findings: Refactor nucleus-config.el and gptel-config.el

## Summary

Analysis revealed 4 configuration files totaling ~2450 lines with significant coupling, naming inconsistencies, and mixed concerns. The primary issues are: (1) gptel-ext-tools.el is a 1200-line monolith, (2) nucleus-config.el handles 8+ distinct concerns, (3) tool lists are scattered across 7 variables, and (4) naming uses inconsistent `my/` vs `nucleus-` prefixes.

---

## Key Discoveries

### Discovery 1: File Size Distribution

| File | Lines | Responsibilities |
|------|-------|------------------|
| `gptel-config.el` | ~50 | Module loader, defaults |
| `nucleus-config.el` | ~500 | Prompts, presets, tools, UI, directives |
| `gptel-ext-tools.el` | ~1200 | Async tools, registration, subagents |
| `gptel-ext-core.el` | ~800 | FSM, curl, doom-loop, reasoning |

**Impact:** gptel-ext-tools.el alone is 50% of the codebase.

---

### Discovery 2: Tool List Proliferation

7 different tool list variables across 3 files:

```elisp
;; nucleus-config.el (5 variables)
nucleus--gptel-agent-core-tools
nucleus--gptel-agent-nucleus-tools
nucleus--gptel-agent-snippet-tools
my/gptel-plan-readonly-tools
my/gptel-agent-action-tools

;; gptel-ext-tools.el (2 variables)
my/gptel-tools-readonly
my/gptel-tools-action
```

**Impact:** Unclear which is canonical, leads to confusion.

---

### Discovery 3: Naming Chaos

Three different naming conventions:
- `my/gptel-*` — user prefix (should be package-specific)
- `nucleus-*` — public package API
- `nucleus--*` — internal functions (double dash)

**Impact:** Inconsistent naming makes API unclear.

---

### Discovery 4: Circular/Deferred Dependencies

```elisp
;; nucleus-config.el defers to gptel-config
(with-eval-after-load 'gptel-config
  (nucleus--register-gptel-directives))

;; gptel-ext-tools.el references nucleus variables
(setq my/gptel-tools-readonly ...)
```

**Impact:** Load order matters; deferred execution makes debugging harder.

---

### Discovery 5: gptel-ext-tools.el Contains Too Much

Single 1200-line file contains:
- 5 async tool implementations (Bash, Grep, Glob, Edit, ApplyPatch)
- 20+ tool registrations
- Subagent delegation system
- Preview system
- Self-test functions
- Utility functions

**Impact:** Violates single responsibility; hard to navigate and test.

---

## Target Structure

```
lisp/
├── gptel-config.el              # Entry point
├── nucleus-config.el            # Backward-compat shim
└── modules/
    ├── gptel-ext-core.el        # Keep (FSM, curl, doom-loop)
    ├── gptel-ext-tools.el       # Split into 8 files
    ├── gptel-tools-bash.el      # NEW: Async Bash
    ├── gptel-tools-grep.el      # NEW: Async Grep
    ├── gptel-tools-glob.el      # NEW: Async Glob
    ├── gptel-tools-edit.el      # NEW: Async Edit
    ├── gptel-tools-apply.el     # NEW: ApplyPatch
    ├── gptel-tools-agent.el     # NEW: Subagent delegation
    ├── gptel-tools-preview.el   # NEW: Preview system
    ├── gptel-tools.el           # NEW: Tool registry
    ├── nucleus-tools.el         # NEW: Tool definitions (DONE)
    ├── nucleus-prompts.el       # NEW: Prompt loading
    ├── nucleus-presets.el       # NEW: Preset management
    └── nucleus-ui.el            # NEW: Header-line, modeline
```

---

## Tool Consolidation Plan

### nucleus-toolsets (canonical source)

```elisp
(defconst nucleus-toolsets
  '((core . ("Agent" "ApplyPatch" "Bash" "Edit" ...))  ; 17 tools
    (readonly . ("Agent" "Bash" "Eval" "Glob" ...))    ; 12 tools
    (nucleus . ("Agent" ... "preview_file_change" ...)) ; 21 tools
    (snippets . ("Bash" "Edit" "Grep" ...)))           ; 15 tools
```

### Backward Compatibility Aliases

```elisp
(defalias 'nucleus--gptel-agent-core-tools
  (nucleus-get-tools :core))
(defalias 'my/gptel-plan-readonly-tools
  (nucleus-get-tools :readonly))
```

---

## Assumptions Validated

| Assumption | Validated? | Evidence |
|------------|------------|----------|
| Files are too large | Yes | gptel-ext-tools.el = 1200 lines |
| Naming is inconsistent | Yes | `my/` vs `nucleus-` prefixes |
| Tool lists are scattered | Yes | 7 variables in 3 files |
| modules/ is correct location | Yes | Consistent with gptel-ext-* files |

---

## Related Files

| File | Status | Action |
|------|--------|--------|
| `modules/nucleus-tools.el` | Created | Phase 2 complete |
| `nucleus-config.el` | Needs update | Require nucleus-tools.el |
| `gptel-config.el` | Needs update | Require nucleus-tools.el |
| `gptel-ext-tools.el` | Split target | Phase 3 |

---

*Last updated: 2025-01-XX*  
*φ fractal euler | π synthesis | ∃ truth*

