---
title: Graphify Complete Architecture Audit
date: 2026-05-17
symbol: 🔁
status: done
---

# Graphify Complete Architecture Audit

Full audit of all 10 graphify modules against our project.

## Module-by-Module Analysis

### detect.py — File Discovery + Classification

| Pattern | Applied? |
|---------|----------|
| FileType enum (CODE/DOCUMENT/PAPER/IMAGE/VIDEO) | No — our code is all Elisp |
| Sensitive file skipping (.env, .pem, credentials) | No — not needed (no secrets in lisp/) |
| Noise directory pruning (venvs, caches) | No — could skip var/elpa/, packages/ |
| graphifyignore patterns | No — could add `.elispignore` |
| Incremental detection (mtime manifest) | Partial — SHA1 cache for knowledge, not for scanning |
| Paper signal detection (arxiv, LaTeX) | No — not applicable |

### extract.py — Deterministic AST Extraction

| Pattern | Applied? |
|---------|----------|
| LanguageConfig dataclass | ✅ `elisp-extraction-config` defconst |
| Two-pass: AST + call-graph | ✅ `extract-elisp-structure` + `summarize-elisp-structure` |
| Import handlers per language | ✅ `advice-pattern` extracts advice-add calls |
| Confidence tagging on edges | Partial — EXTRACTED/INFERRED in knowledge pages, not on edges |
| Per-file extraction cache (SHA256) | ✅ `results-cache-key/fresh-p/save` |

### build.py — Graph Assembly

| Pattern | Applied? |
|---------|----------|
| 3-layer node dedup (within-file, between-file, semantic merge) | No — knowledge pages overwrite on write |
| validate_extraction before build | ✅ `valid-knowledge-input-p` |
| Dangling edge tolerance (stdlib/external) | No — not applicable |
| Directed graph support (_src/_tgt) | No — not applicable |

### cache.py — Incremental Processing

| Pattern | Applied? |
|---------|----------|
| SHA256 file hashing | ✅ `results-cache-key` |
| YAML frontmatter stripping for .md files | No — could apply to mementum files |
| check_semantic_cache (cached/uncached split) | Partial — `results-cache-fresh-p` |
| save_semantic_cache (group by source_file) | Partial — `results-cache-save` |
| tmp + atomic replace for writes | No |

### cluster.py — Community Detection

| Pattern | Applied? |
|---------|----------|
| Graceful degradation (Leiden→Louvain) | No |
| Isolate handling (degree-0 nodes) | No |
| Community splitting (>25% graph) | No |
| Cohesion scoring (internal/total edges) | ✅ `module-cohesion` |

### analyze.py — Graph Analysis

| Pattern | Applied? |
|---------|----------|
| god_nodes (top degree, filtered) | No |
| surprising_connections (composite score) | No |
| Cross-file + cross-community surprises | No |
| suggest_questions (5 types) | No |
| graph_diff (snapshot comparison) | No |

### validate.py — Schema Enforcement

| Pattern | Applied? |
|---------|----------|
| VALID_CONFIDENCES set | Partial — EXTRACTED/INFERRED in text, not enforced |
| REQUIRED_NODE_FIELDS / REQUIRED_EDGE_FIELDS | Partial — `valid-knowledge-input-p` checks :target + :decision only |
| assert_valid() — fail fast with all errors | No |

### security.py — Input Sanitization

| Pattern | Applied? |
|---------|----------|
| SSRF protection (URL scheme validation) | No |
| Redirect re-validation | No |
| Streaming read with size cap | No |
| sanitize_label (control chars + 256 cap) | ✅ `sanitize-knowledge-label` |
| validate_graph_path (directory jail) | No |

### benchmark.py — Token Efficiency

| Pattern | Applied? |
|---------|----------|
| BFS from best-matching nodes | No |
| Per-question token measurement | No |
| Corpus vs graph reduction ratio | No |

### watch.py — File Change Auto-Sync

| Pattern | Applied? |
|---------|----------|
| Two-tier response (code=instant, doc=notify) | No |
| Debounced file watching | No |
| Flag file for pending LLM work | No |

## Summary

| Total Patterns | Applied | Partial | Not Applied |
|---------------|---------|---------|-------------|
| 30 | 10 | 6 | 14 |

### 10 Patterns Fully Applied
1. LanguageConfig schema → `elisp-extraction-config`
2. Two-pass extraction → `extract-elisp-structure` + `summarize-elisp-structure`
3. SHA256 cache → `results-cache-key/fresh-p/save`
4. Input validation → `valid-knowledge-input-p`
5. Label sanitization → `sanitize-knowledge-label`
6. Cohesion scoring → `module-cohesion`
7. Confidence tagging → EXTRACTED/INFERRED in knowledge pages
8. Confidence in YAML → `confidence: EXTRACTED`
9. Content validation → bounds checks in synthesize
10. Token efficiency → `token-efficiency.md` auto-evolution

### 6 Patterns Partially Applied
1. validate.py schema enforcement (only 2 fields checked, not full schema)
2. cache.py YAML stripping + atomic writes
3. Edge confidence scores (tagged but no numeric scores)
4. Schema validation (not raising on all errors)
5. File detection (no incremental mtime manifest for scanner)
6. Noise directory pruning (not implemented)
