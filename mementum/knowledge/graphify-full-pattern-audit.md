---
title: Graphify Architecture — Full Pattern Audit
date: 2026-05-17
symbol: 💡
---

# Graphify Architecture — Full Pattern Audit

## Already Applied (3 patterns)

| graphify | Our Implementation |
|----------|-------------------|
| validate.py | `valid-knowledge-input-p` — rejects results without :target/:decision |
| security.py sanitize_label | `sanitize-knowledge-label` — strips control chars, caps 256 |
| Confidence tags | EXTRACTED/INFERRED in knowledge page sections |

## Not Yet Applied (4 patterns)

### 1. SHA256 Cache (cache.py)
**graphify**: `check_semantic_cache(files)` returns `(cached, uncached)` split. SHA256 of file content. Markdown body-only hashing skips YAML metadata changes. `/graphify --update` re-runs only changed files.

**Our gap**: Self-evolution re-analyzes all experiment results every cycle. No incremental caching. Target files that haven't changed get re-analyzed.

**Implementation idea**: Hash each `results.tsv` file. Skip synthesis for strategies whose experiment results haven't changed since last run.

### 2. LanguageConfig Schema (extract.py)
**graphify**: Each language has a `LanguageConfig` dataclass with typed fields: class_types, function_types, import_types, call_types, name_field, body_field. Adding a language = adding a config struct.

**Our gap**: Our code analysis for target selection uses ad-hoc string matching and heuristics. No structured schema for what constitutes a "function" or "import" in Elisp.

**Implementation idea**: Define Elisp-specific extraction config: defun types, defvar types, require patterns, provide patterns. Use for deterministic pre-pass before LLM analysis.

### 3. Two-Pass Extraction (extract.py)
**graphify**: Pass 1: tree-sitter AST (no LLM cost) extracts classes, functions, imports. Pass 2: Call-graph walk extracts INFERRED `calls` edges. Pass 3: rationale/docstring extraction. Only docs/papers/images need LLM.

**Our gap**: ALL analysis uses LLM. No deterministic pre-pass. Every experiment prompt includes the full file content via Read tool.

**Implementation idea**: Add a `defun`/`defvar`/`require` scanner that runs on the raw .el source. Feed the structure summary + only relevant sections to the LLM, reducing prompt size and token cost.

### 4. Edge Confidence Schema
**graphify**: Every edge has `"confidence": "EXTRACTED"|"INFERRED"|"AMBIGUOUS"` and `"confidence_score": 0.0-1.0`. Clean graph only includes valid source/target nodes.

**Our gap**: Mementum memories and knowledge pages don't have edge-level confidence. The knowledge page YAML has `insight-quality` based on keep rate, but individual claims within the page aren't tagged.

**Implementation idea**: Add `confidence: EXTRACTED` to knowledge page YAML front matter. Tag individual bullet points in knowledge pages as EXTRACTED (from TSV stats) or INFERRED (from LLM pattern analysis).
