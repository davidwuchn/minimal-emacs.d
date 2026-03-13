# Code_* Tools — Unified Structural Editing

## Overview

The `Code_*` tools provide a unified, KISS (Keep It Simple, Stupid) interface for code intelligence and structural editing across all supported languages. They leverage tree-sitter AST parsing for perfect syntax handling and LSP integration for project-wide intelligence.

## The Five Code_* Tools

| Tool | Purpose | When to Use |
|------|---------|-------------|
| [`Code_Map`](#code_map) | File structure/outline | FIRST tool when opening unfamiliar files |
| [`Code_Inspect`](#code_inspect) | Extract function/class by name | Read exact implementation before editing |
| [`Code_Replace`](#code_replace) | Structural replacement | Modify functions (REQUIRED for Lisp/Python/Rust) |
| [`Code_Usages`](#code_usages) | Find all references | Before renaming or impact analysis |
| [`Diagnostics`](#diagnostics) | Project diagnostics | Verify changes after editing |

## Workflow

```
1. Code_Map      → Understand file structure
2. Code_Inspect  → Extract exact function
3. Code_Replace  → Modify function (AST-guaranteed balanced)
4. Code_Usages   → Find all references (before renaming)
5. Diagnostics    → Verify no errors
```

---

## Code_Map

**Purpose**: Get a high-level overview of all functions, classes, and definitions in a file.

### Usage
```json
Code_Map{file_path: "path/to/file.py"}
```

### Returns
Ordered list of all defined symbols (functions, classes, methods).

### Example
```
Code_Map{file_path: "src/utils.py"}
→ File map for src/utils.py:
  calculate_totals
  MyClass
  method_one
  process_data
```

### Supported Languages
Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JavaScript, any tree-sitter supported language.

---

## Code_Inspect

**Purpose**: Extract the exact, perfectly balanced implementation block of a function or class by name.

### Usage
```json
Code_Inspect{node_name: "function_name", file_path?: "optional/path.py"}
```

### Parameters
- `node_name` (required): Exact name of function/class to extract
- `file_path` (optional): Path to file. **If omitted, searches entire project!**

### Returns
Complete, perfectly balanced code block with correct indentation/parentheses.

### Examples
```
# With file path
Code_Inspect{node_name: "calculate_totals", file_path: "src/utils.py"}
→ Code block 'calculate_totals' from src/utils.py:
  
  def calculate_totals(data):
      total = 0
      for item in data:
          total += item['value']
      return total

# Without file path (auto-searches project)
Code_Inspect{node_name: "helper_function"}
→ Found in src/helpers.py:
  
  def helper_function(x, y):
      return x + y
```

### Notes
- Uses tree-sitter AST for perfect extraction
- Guarantees balanced parentheses/brackets
- Auto-searches workspace if `file_path` omitted (uses `AST_Find_Workspace`)

---

## Code_Replace

**Purpose**: Surgically replace an exact function or class by name with new code. **GUARANTEES perfectly balanced parentheses/brackets.**

### ⚠️ CRITICAL: When to Use
- **MUST use** for Lisp languages (.el, .clj, .cljs, .cljc, .edn)
- **MUST use** for Python, JavaScript, Rust when modifying existing functions
- **NEVER use** standard `Edit` for function modifications in these languages

### Usage
```json
Code_Replace{
  file_path: "path/to/file.py",
  node_name: "function_name",
  new_code: "def function_name():\n    return 'new'"
}
```

### Parameters
- `file_path` (required): Path to the file containing the function
- `node_name` (required): Exact name of function/class to replace
- `new_code` (required): Complete new implementation (must be syntactically valid!)

### Returns
Success message or error if node not found / syntax invalid.

### Example
```json
Code_Replace{
  file_path: "src/utils.py",
  node_name: "calculate_totals",
  new_code: "def calculate_totals(data):\n    return sum(item.get('value', 0) for item in data)"
}
→ Successfully replaced 'calculate_totals' in src/utils.py
```

### ⚠️ Safety Features
- **Syntax validation**: Rejects code with unbalanced parentheses/brackets
- **Preview**: Shows diff before applying (if preview enabled)
- **Atomic**: Either fully replaces or fully reverts (no partial edits)

### Supported Languages
Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JavaScript

---

## Code_Usages

**Purpose**: Find all usages/references of a symbol (function, class, variable) across the entire project.

### Usage
```json
Code_Usages{node_name: "function_name"}
```

### Parameters
- `node_name` (required): Symbol/function/class name to find usages for

### Returns
List of all locations where the symbol is referenced, with `file:line:context`.

### Example
```
Code_Usages{node_name: "calculate_totals"}
→ Found 5 usages of 'calculate_totals':

  src/utils.py:10: def calculate_totals(data):
  src/main.py:25: result = calculate_totals(items)
  src/main.py:42: return calculate_totals(filtered)
  src/reports.py:15: from utils import calculate_totals
  src/reports.py:78: total = calculate_totals(data)
```

### ⚠️ Smart Fallback Chain
1. **LSP References** (if eglot server is running)
   - Semantic understanding of references
   - Distinguishes definition from usages
   - Handles imports, aliases, method calls

2. **Ripgrep Search** (if no LSP or LSP finds nothing)
   - Fast text-based search across project
   - Excludes .pyc, .elc, __pycache__, etc.
   - Returns raw matching lines

---

## Diagnostics

**Purpose**: Get diagnostics (errors and warnings) for a file or entire project.

### Usage
```json
Diagnostics{file_path: "lisp/eca-ext.el"}  ; Single file
Diagnostics{}                                ; Entire project
Diagnostics{all: true}                      ; Include notes
```

### Returns
Formatted list of all diagnostics with `file:line:type:message` format.

### Examples

**Single Emacs Lisp file:**
```
Diagnostics{file_path: "lisp/eca-ext.el"}
→ === checkdoc ===
  lisp/eca-ext.el:45: First sentence should ...
  === byte-compile ===
  ✓ No byte-compile warnings
  === package-lint ===
  ✓ No package-lint issues
```

**Project-wide:**
```
Diagnostics{}
→ src/utils.py:42 [Error] Undefined variable 'undefined_var'
  src/main.py:15 [Warning] Unused import 'os'
```

### Smart Language Detection

| File Type | Linter Chain |
|-----------|-------------|
| `.el` | checkdoc → byte-compile → package-lint |
| `.py` | LSP → ruff → flake8 |
| `.js/.ts` | LSP → npm run lint → eslint |
| `.rs` | LSP → cargo check |
| Other | LSP diagnostics |

### ⚠️ Smart Fallback Chain
1. **LSP Diagnostics** (if eglot server is running)
   - Type errors, undefined vars, import errors
   - Language-specific checks (ruff, pylint, rustc, etc.)

2. **CLI Linters** (if no LSP server)
   - Python: `ruff check .` → `flake8 .`
   - JavaScript: `npm run lint` → `npx eslint .`
   - Rust: `cargo check`
   - Emacs Lisp: checkdoc + byte-compile + package-lint
   - Reports: "No linter errors (ToolName)" if clean

### Notes
- Pass `file_path` for single-file diagnostics
- Omit `file_path` for project-wide diagnostics
- For `.el` files, always uses built-in checkdoc/byte-compile
- Returns "No diagnostics found" if code is clean

---

## Implementation Details

### Tree-sitter AST Integration
All `Code_*` tools use Emacs 29+'s built-in tree-sitter parser for structural understanding:
- Perfect parenthesis/bracket balancing
- Syntax-aware extraction and replacement
- Language-agnostic interface

### LSP Integration
- `Diagnostics` integrates with `flymake--project-diagnostics` for LSP errors
- `Code_Usages` uses `xref-find-references` for semantic reference finding
- Automatic fallback to CLI tools when LSP unavailable

### Configuration
Tree-sitter grammars are configured in `post-early-init.el`:
```elisp
(setq treesit-extra-load-path
      (list (expand-file-name "var/tree-sitter/" user-emacs-directory)))
```

### Tool Registration
Tools are registered in `lisp/modules/gptel-tools-code.el` and included in nucleus toolsets (`lisp/modules/nucleus-tools.el`).

---

## Preview

**Purpose**: Preview file changes or patches with a diff view before applying.

### Usage
```json
// File change mode
Preview{path: "src/utils.py", replacement: "new content"}

// Patch mode (raw unified diff)
Preview{patch: "--- a/file\n+++ b/file\n..."}
```

### Parameters
- `path` (optional): Target file path (file change mode)
- `original` (optional): Original content (auto-read from file if omitted)
- `replacement` (optional): Replacement content (file change mode)
- `patch` (optional): Unified diff content (patch mode)

### Confirmation

After displaying the diff, prompts in minibuffer:

| Key | Action |
|-----|--------|
| `y` | Apply this change |
| `n` | Abort this change |
| `N` | Never ask again (auto-apply rest of session) |
| `q` | Quit |

### Configuration

```elisp
;; Disable preview entirely (auto-apply all changes)
(setq gptel-tools-preview-enabled nil)

;; Re-enable confirmations after "N"
M-x gptel-tools-preview-reset-confirmation
```

### Use Cases
- Review AI-suggested changes before applying
- Batch operations: answer "N" after first few reviews
- CI/CD: set `gptel-tools-preview-enabled` to `nil`

## See Also
- [AGENTS.md](../AGENTS.md) — Bootstrap principles
- [STATE.md](../STATE.md) — Current configuration status
- [assistant/prompts/tools/](../assistant/prompts/tools/) — Individual tool prompt docs

## Automatic Parser Installation

Tree-sitter language parsers are **automatically installed** on first use:

```elisp
;; In lisp/init-treesit.el
(setq treesit-auto-install 'auto)  ; Auto-install parsers when needed
(global-treesit-auto-mode)         ; Enable tree-sitter modes automatically
```

### Supported Parsers
The following parsers are pre-configured with ABI14-compatible revisions:

| Language | Grammar Repository | ABI14 Revision |
|----------|-------------------|----------------|
| Elisp | `Wilfred/tree-sitter-elisp` | `1.2` |
| Python | `tree-sitter/tree-sitter-python` | `v0.21.0` |
| Rust | `tree-sitter/tree-sitter-rust` | `v0.21.0` |
| Clojure | `sogaiu/tree-sitter-clojure` | `master` |

### Manual Installation (Optional)
To pre-install parsers before first use:

```elisp
M-x treesit-install-language-grammar RET python RET
M-x treesit-install-language-grammar RET elisp RET
M-x treesit-install-language-grammar RET rust RET
M-x treesit-install-language-grammar RET clojure RET
```

Installed grammars are stored in `~/.emacs.d/var/tree-sitter/`.
