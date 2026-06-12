---
title: Clojure-First Multi-Platform Architecture — Strategic Decision
status: active
category: architecture
tags: clojure, clojure-dialects, multi-platform, cross-compile, language-strategy
related: gptel-ext-brepl, deep-searcher-vs-ov5-gaps, launch-fast-vs-ov5-gaps
created: 2026-06-12
---

# Clojure-First Multi-Platform Architecture

**Source:** [clojure.cc](https://clojure.cc/) — catalog of 39 Clojure dialects across every major platform (2026-06-12)

**Decision:** OV5 should target Clojure as its single experiment language, using Clojure dialects to reach every platform. This eliminates the need for per-language test/lint/deploy backends.

---

## 1. The Problem

OV5's experiment loop works on any language (LLMs generate changes), but its tooling (test runner, linter, fixer, deploy) is Elisp-specific. To support non-Emacs codebases, we previously proposed per-language backends:

```
❌ OLD: JS test runner + Python test runner + Go test runner + ...
❌ OLD: ESLint + pylint + golangci-lint + ...
❌ OLD: Prettier + Black + gofmt + ...
```

This is pathologically scaling — each new language adds a new backend.

## 2. The Insight

There are **39 Clojure dialects** targeting every major platform. Clojure is a Lisp with:
- Consistent syntax across all dialects
- `clojure.test` as a universal test framework
- `clj-kondo` as a universal linter (works on all dialects)
- Clojure formatters (`cljfmt`, `zprint`) work across dialects

If OV5 writes Clojure, the dialect transpiler handles platform-specific output. One language, one toolchain, every platform.

```
✅ NEW: Clojure test runner → test on any platform via dialect
✅ NEW: clj-kondo → lint on any platform
✅ NEW: cljfmt/zprint → format on any platform
✅ NEW: dialect-specific transpile → deploy to any platform
```

## 3. Platform Coverage

| Platform | Dialect(s) | Status |
|----------|-----------|--------|
| **JVM** | Clojure | Production |
| **JavaScript / Web** | ClojureScript, Squint, Cherry, nbb, Scittle | Production |
| **Shell / scripting** | Babashka, Cream | OV5 already uses |
| **C++ / native** | Jank, Ferret, cljrs (MLIR/LLVM, GPU) | Active |
| **Go** | Joker, Glojure, let-go, Gloat, go-joker | Active |
| **Erlang / BEAM** | Clojerl | Active |
| **.NET / CLR** | ClojureCLR, clojure-clr-next | Active |
| **Python** | Hy, Basilisp | Active |
| **Rust** | ClojureRS, cljrs | Active |
| **Dart / Flutter** | ClojureDart | Active |
| **PHP** | Phel | Active |
| **C (embedded)** | Carp, JO Clojure | Active |
| **WebAssembly** | ClojureWasm, Gloat | Active |
| **Lua** | Fennel, ClojureFnl | Active |
| **macOS automation** | obb | Niche |
| **VS Code** | Joyride | Niche |

## 4. OV5 ↔ Clojure Alignment

OV5 already has Clojure infrastructure — this isn't a new dependency:

| OV5 component | Clojure tool | Status |
|--------------|-------------|--------|
| REPL | `brepl` (babashka nREPL) | Production |
| Structured store | Datahike (via BB pod) | Production |
| Test runner | `clojure.test` via brepl | Done (2026-06-12) |
| Linter | `clj-kondo` via brepl | Done (2026-06-12) |
| Paren fixer | `brepl balance` | Production |
| ns-order fixer | `gptel-brepl-fix-ns-ordering` | Done (2026-06-12) |
| Formatter | `cljfmt` or `zprint` | Not started |
| Dialect compile | Per-dialect transpiler | Not started |
| Dialect deploy | Platform-specific packaging | Not started |

## 5. What This Means for the Experiment Loop

**Current (Elisp-only):**
```
Target .el file → ERT tests → check-parens → byte-compile → keep/discard
```

**Future (Clojure-universal):**
```
Target .clj file → clojure.test → clj-kondo → cljfmt → dialect-transpile → platform-deploy → keep/discard
```

The same `.clj` file can be an Amazon Chrome extension (ClojureScript→JS), a CLI tool (Babashka), a backend service (JVM Clojure), or a native binary (Jank/Carp).

## 6. Implementation Path

| Phase | What | Effort |
|-------|------|--------|
| **0. Test + Lint** | clojure.test + clj-kondo via brepl | Done |
| **1. Format** | Add `gptel-brepl-format` → cljfmt/zprint | Low |
| **2. Target any .clj** | OV5 experiment loop selects `.clj` targets | Done (category `:clojure`) |
| **3. Multi-dialect build** | `bb.edn` task that transpiles to target dialect | Medium |
| **4. Platform deploy** | Per-platform packaging (npm, pip, binary, etc.) | High |
| **5. Full loop** | Experiment → test → lint → format → build → deploy → monitor | Future |

## 7. Why This Over Per-Language Backends

| Factor | Per-language backends | Clojure-first |
|--------|----------------------|---------------|
| Languages supported | N (each needs backend) | All (via dialects) |
| Test frameworks to maintain | N | 1 (clojure.test) |
| Linters to maintain | N | 1 (clj-kondo) |
| Fixers to write | N × M patterns | 1 set for Clojure |
| LLM prompt complexity | Language-specific | One language, all contexts |
| OV5 self-evolution surface | Per language | One language |
| Existing OV5 infra reuse | Low | High (brepl, Datahike, BB) |

---

## 8. Related Files

- `lisp/modules/gptel-ext-brepl.el` — Clojure REPL, test runner, linter, fixers
- `clj/ov5/` — OV5 Clojure modules (world_store, branch, analysis, test_runner)
- `bb.edn` — Babashka configuration (Datahike pod)
- `mementum/knowledge/deep-searcher-vs-ov5-gaps.md` — prior gap analysis
- `mementum/knowledge/launch-fast-vs-ov5-gaps.md` — SaaS patterns (would be Clojure-targetable)
