---
title: Launch Fast vs CreatorOS — 3-Surface Gap Analysis
status: active
category: architecture
tags: launch-fast, creatoros, chrome-extension, MCP, three-surface-pattern
related: launch-fast-vs-ov5-gaps, creator-product-matching-engine, clojure-first-multiplatform-architecture
created: 2026-06-12
---

# Launch Fast vs CreatorOS — 3-Surface Gap Analysis

**Re-analysis after building CreatorOS demo (5 modules, 31 tests).**

Launch Fast started as a Chrome extension for Amazon sellers and grew into a $41-166/mo SaaS with a web dashboard and MCP server. CreatorOS has the core engine (sources → profit → scoring → matching) but is missing the distribution surfaces that make Launch Fast a product people pay for.

## 1. What Launch Fast Has That CreatorOS Doesn't

| Surface | Launch Fast | CreatorOS | Priority |
|---------|-------------|-----------|----------|
| **Chrome Extension** | ✅ Injects product data on Amazon pages | ❌ | P0 |
| **Web Dashboard** | ✅ React/Next.js SPA | ❌ (CLI demo only) | P1 |
| **MCP Server** | ✅ Exposes tools to Claude/Cursor | ❌ | P1 |
| **Payment/Subscription** | ✅ Stripe ($41-166/mo) | ❌ | P1 |
| **CLI Tool** | ✅ `deepsearcher load/query` | ✅ `bb -f demo.clj` | Done |

## 2. Why the Chrome Extension Matters

Launch Fast's core insight: **data should appear where the user already works.** Amazon sellers spend 90% of their time on Amazon product and search pages. Launch Fast injects market signals (revenue, BSR, reviews, margins) directly onto those pages. No tab switching. No context loss.

CreatorOS's equivalent: TikTok creators spend their time on TikTok Creator Marketplace, Amazon product pages, and their own analytics dashboards. The extension should overlay product intelligence on all three:

| Page | What CreatorOS Shows |
|------|---------------------|
| TikTok Creator Marketplace | Product picks with margins, risk scores, supplier links |
| Amazon product pages | Creator-relevant: "This product matches 3 of your audience segments" |
| Creator analytics dashboard | Inline match scores for products the creator is considering |

## 3. Implementation Path (Clojure → CLJS)

CreatorOS is Clojure. OV5's Clojure-first strategy means:

```
clj/creatoros/matching.clj  ← shared engine (already built)
clj/creatoros/extension/content.cljs  ← CLJS → JS content script
clj/creatoros/dashboard/    ← Reagent SPA
clj/creatoros/mcp/          ← MCP server wrapper
```

The Chrome extension needs:
- `manifest.json` (permissions for Amazon + TikTok + RedNote)
- `content.cljs` (product overlay injection)
- `popup.cljs` (quick product search)

**OV5 builds this autonomously.** The experiment loop generates the extension code. The Clojure toolchain (test/lint/format/fix) validates it. Estimated effort: 2-3 weeks of OV5 experiments.

## 4. MCP Server: Exposing the Engine

Launch Fast's MCP server lets Claude/Cursor agents call `research_products`, `amazon_keyword_research`, `supplier_research`. CreatorOS should expose:

| MCP Tool | Maps to |
|----------|---------|
| `match_products` | `matching.clj` |
| `score_product` | `scoring.clj` |
| `calculate_profit` | `profit.clj` |
| `fetch_sources` | `sources.clj` |

This turns CreatorOS from a demo into a tool any AI agent can use. OV5's experiment loop can wire this up — the API surface is already defined by the module functions.

## 5. What Launch Fast Still Does Better

| Area | Launch Fast Advantage |
|------|---------------------|
| UX | Polished Chrome extension + React dashboard |
| Data | Real Amazon/Supplier APIs, not sample data |
| Revenue | $41-166/mo with paying customers |
| Distribution | Chrome Web Store listing |
| MCP | Production-ready tool exposure |

## 6. What CreatorOS Already Does Better

| Area | CreatorOS Advantage |
|------|---------------------|
| Engine | Multi-source (Amazon + Reddit + AliExpress + Google Trends) |
| Scoring | 5-dimension composite grading (demand, margin, competition, trend, community) |
| Multi-platform | Single codebase targets 3 products (Amazon + TikTok + RedNote) |
| Self-improving | OV5 experiments improve the engine daily |
| Cost | $200/mo flat operating cost |
| Tests | 52 assertions, 0 failures, CI-ready |

## 7. Related Files

- `mementum/knowledge/launch-fast-vs-ov5-gaps.md` — original Launch Fast analysis
- `CREATOROS.md` — product spec and investor deck
- `clj/creatoros/` — working demo code
