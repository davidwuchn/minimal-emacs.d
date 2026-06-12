---
title: Launch Fast vs OV5 - Chrome Extension Patterns Gap Analysis
status: active
category: architecture
tags: launch-fast, chrome-extension, contextual-overlay, inline-intelligence, SaaS
related: deep-searcher-vs-ov5-gaps, gptel-tools-agent, gptel-auto-workflow-self-audit
created: 2026-06-12
---

# Launch Fast vs OV5 - Chrome Extension Patterns Gap Analysis

**Source:** [launchfastlegacyx.com](https://launchfastlegacyx.com/) — Amazon seller Chrome extension (2026)

Launch Fast is a Chrome extension that overlays Amazon seller intelligence onto product and search pages. It injects market data (revenue, BSR, reviews, margins, keyword gaps, supplier info) directly into the pages sellers already visit. It also has a web dashboard for deep research and an optional MCP server for AI agents — but the core product is the Chrome extension.

OV5 is an Emacs-native self-evolving system. It does not need a Chrome extension — but it can learn from the **contextual overlay pattern** that Launch Fast exemplifies.

---

## 1. The Chrome Extension Pattern

Launch Fast's Chrome extension provides three things:

| What it does | How |
|-------------|-----|
| **Inline data injection** | Revenue, BSR, margins, keyword gaps shown on Amazon product pages |
| **Context preservation** | Seller stays on Amazon — no tab switching to a separate research tool |
| **Decision support at the point of action** | Profit estimates, supplier info, and IP risks visible before clicking "order" |

This is the **contextual intelligence** pattern: surface the right data at the right moment in the user's existing workflow.

---

## 2. OV5 Equivalent: Contextual File Intelligence

OV5 is already inside Emacs — that's its "Chrome." Every `.el` file you edit IS the page where data should be overlaid. The question is: what intelligence belongs on each file?

| Launch Fast pattern | OV5 equivalent | Current state |
|--------------------|----------------|---------------|
| Revenue/BSR on product page | Keep-rate, experiment count, last outcome on target file | Missing |
| Margin/profit estimate | Complexity score, test coverage impact estimate | Missing |
| Supplier info | Related memories, knowledge pages about this file's patterns | Partial (mementum recall exists but not inline) |
| Keyword gaps | Uncovered audit issues, pending self-heal fixes | Missing |
| "Don't source this" warning | "Don't experiment on this — baseline is unstable" | Missing |

---

## 3. Actionable Gaps

### 3.1 Inline Experiment Overlay (Highest Priority)

**Gap:** When editing a file, there is no indication of its experiment history, keep-rate, or last outcome. You have to run `gptel-auto-workflow-status` or `git log` separately.

**What Launch Fast does:** Shows market grade (A1-F9), revenue, BSR directly on the Amazon product page.

**Possible path:**
- Add a minor mode `gptel-file-intel-mode` that shows experiment data in the header-line or a side window
- Per-file: last N experiments, keep-rate, best strategy, last backend used
- Warn when a file has 3+ consecutive discarded experiments (like Launch Fast's grade system A-F)

### 3.2 Decision-Grade Overlay

**Gap:** Files have no visible "quality grade" or "risk level" that tells you whether experimenting on them is a good idea.

**What Launch Fast does:** Every product gets an A-F grade (A1-A9, B1-B9, etc.) based on revenue, reviews, competition, margins.

**Possible path:**
- Assign each target file a grade based on: experiment success rate, test coverage, complexity, days-since-last-kept
- Show grade in the mode-line or header-line
- Color-code: green (healthy, experiment), yellow (stale, needs attention), red (unstable, avoid)

### 3.3 Supplier-Like Knowledge Routing

**Gap:** When editing a function, there's no quick way to see which other files use similar patterns or share the same ontology category.

**What Launch Fast does:** Shows supplier info, MOQ, pricing directly on the product page — you see the supply chain without leaving the product.

**Possible path:**
- Show "Related files" or "Same category" in a side panel when editing a target
- Link to mementum memories that reference this file or its patterns
- Show semantic cluster members (π Synthesis candidates)

### 3.4 Risk Warning Before Action

**Gap:** No warning when you're about to edit a file that has unstable baselines, pending self-heal issues, or recent failed experiments.

**What Launch Fast does:** IP check — warns if a product has patent/trademark risk before you source it.

**Possible path:**
- Before-save hook: warn if file has unreviewed self-heal fixes, pending audit issues, or stale baselines
- "Safety score" overlay: green/yellow/red based on audit + experiment history

---

## 4. What OV5 Can DO For a Codebase Like Launch Fast

If OV5 were applied to Launch Fast's codebase (React/Next.js dashboard + Chrome extension JS + backend API), here is what works today and what needs tooling:

### Works Today (language-agnostic experiment loop)

| OV5 capability | How it applies to a JS/web codebase |
|---------------|-------------------------------------|
| **100+ experiments/month** | LLMs generate JS/TS changes; OV5 runs them in isolated git worktrees |
| **~20% keep-rate** | 1 in 5 experiments passes all gates and ships |
| **7-gate quality pipeline** | Tests + AI grading + complexity gate + review before merge |
| **12-backend AI routing** | Auto-failover across providers for ALL LLM calls (AI Overview, listing builder, etc.) |
| **Mementum memory** | Every experiment outcome, every production incident, every customer insight persists |
| **Monitoring agent** | Detects failures in the SaaS production system, proposes architectural fixes |
| **Self-healing** | Detects and auto-fixes syntax errors, unguarded calls, type mismatches |
| **World Store** | Structured storage for market research data, experiment outcomes, supplier data |
| **Ontology learning** | Learns which code patterns succeed/fail, propagates fixes to similar files |

### Needs Adding (JS/web-specific tooling)

| Gap | Current state | What's needed |
|-----|--------------|---------------|
| **Test runner** | ERT (Elisp only) | Jest / Vitest / Playwright integration |
| **Chrome extension testing** | None | Extension-specific test harness (manifest validation, content script isolation) |
| **JS-aware self-heal fixers** | Elisp-only (paren balance, nil-guard, etc.) | JS fixers: missing await, undefined guards, prop-type validation |
| **Byte-compile gate equivalent** | `byte-compile-error-on-warn` (Elisp) | ESLint / TypeScript strict mode as a gate |
| **Chrome Web Store deploy** | Git merge to main | Automated extension packaging + store submission |
| **Domain ontologies** | Code-quality categories only | Amazon seller concepts: BSR, FBA, market grades, keyword difficulty |

### The Bottleneck

OV5's experiment loop is **language-agnostic at the LLM level** — any LLM can generate JS/TS/Python changes. But it's **Elisp-specific at the tooling level** — tests, self-heal fixers, byte-compile checks, and quality gates are all Elisp-native.

The fix is not to rewrite OV5 for JS. It is to **make OV5's tooling pluggable by language**: swap ERT for Jest, swap `check-parens` for ESLint, swap `byte-compile-error-on-warn` for `tsc --noEmit`. The experiment loop, 7-gate pipeline, memory, and routing are already language-agnostic.

---

## 5. What OV5 Already Does Better

| Area | OV5 Advantage |
|------|---------------|
| Editor integration | Emacs-native — no Chrome extension needed; OV5 IS the environment |
| Self-evolution | Launch Fast is a static tool; OV5 evolves |
| Memory persistence | Git-based mementum + Datahike World Store |
| Tool depth | 20+ code manipulation tools vs Launch Fast's research/listing tools |
| Cost | Free/open-source vs $41-166/mo |

---

## 5. Synthesis

Launch Fast's Chrome extension is a **contextual decision-support layer** — it puts the right data on the right page at the right time. OV5's equivalent opportunity is to make experiment intelligence visible *on the files being edited*, not buried in status buffers and git logs.

The simplest high-leverage addition is a `gptel-file-intel-mode` that shows per-file experiment history and a quality grade in the header-line. From there, inline memory recall and risk warnings before save would progressively build OV5's "extension" layer.

---

## 6. Related Files

- `lisp/modules/gptel-auto-workflow-self-audit.el` — could feed file health grades
- `lisp/modules/gptel-auto-workflow-ontology-router.el` — category routing data per file
- `lisp/modules/gptel-tools-memory.el` — mementum recall for inline memory overlay
- `mementum/knowledge/deep-searcher-vs-ov5-gaps.md` — prior gap analysis
