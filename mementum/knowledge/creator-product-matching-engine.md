---
title: Creator Product-Matching Engine — OV5 for the TikTok Economy
status: active
category: architecture
tags: tiktok, creator-economy, product-matching, GTM-mayor, amazon, reddit, aliexpress, data-pipeline
related: gptel-auto-workflow-research, gptel-ext-world-store, clojure-first-multiplatform-architecture
created: 2026-06-12
depends-on: clojure-first-multiplatform-architecture
---

# Creator Product-Matching Engine

**Problem:** A TikTok creator with 50K followers needs to know which 3 products to promote. They don't have time to research Amazon, read Reddit, check AliExpress prices, and track TikTok trends. They need: "Here are your top 3 product picks for this week, with margins and why."

**Solution:** OV5's existing infrastructure is a product-matching engine. Repoint the GTM Mayor at product data sources, cross-reference with the ontology, output a ranked matrix per creator.

---

## 1. How OV5 Solves This Without TikTok's API

| Step | OV5 Component | Data Source | Output |
|------|--------------|-------------|--------|
| **Scan** | GTM Mayor (research strategies) | Amazon BSR, Reddit product mentions, AliExpress pricing, Google Trends, TikTok hashtag | Raw product signals |
| **Distill** | Allium v3 (behavioral compiler) | Research findings → structured specs | Normalized product facts |
| **Classify** | Ontology router (categorization) | Product × creator-niche × margin-band | Enriched entities |
| **Store** | World Store (Datahike) | Product entities with source attribution | Queryable fact DB |
| **Score** | Experiment loop | Keep-rate on product recommendations | Ranked per-creator matrix |
| **Deliver** | Dashboard (Reagent SPA) | Per-creator product matrix | "Your top 3 this week" |

## 2. Data Sources — No Scraping Blockers

| Source | What OV5 extracts | Access method | Risk |
|--------|-------------------|---------------|------|
| **Amazon** | BSR trajectory, review count, price history, "also bought" graph | Keepa-style scraping or Product API | Low (public pages) |
| **Reddit** | r/SkincareAddiction, r/AsianBeauty, r/MakeupAddiction — product mentions, "holy grail" frequency, sentiment | Reddit API / Pushshift | Low (public API) |
| **AliExpress / 1688** | Wholesale price, MOQ, supplier count, shipping terms | Public product pages | Low |
| **Google Trends** | Search volume trajectory, regional breakdown, related queries | Pytrends or API | Low (official API) |
| **TikTok hashtags** | Product appearance in trending videos, hashtag velocity | Public web (no API needed) | Low |

## 3. Product Matrix Output

```
Creator: @beautywithling (280K, beauty, 23% engagement rate)
Generated: 2026-06-12

┌────┬─────────────────────┬───────┬─────────┬───────┬──────────┐
│ #  │ Product             │ Cost  │ Retail  │ Margin│ Risk     │
├────┼─────────────────────┼───────┼─────────┼───────┼──────────┤
│ 1  │ Korean sunscreen    │  $8   │  $29    │  67%  │ LOW      │
│    │ stick               │       │         │       │          │
│    │ → Reddit "HG" 4mo   │       │         │       │          │
│    │ → Amazon BSR #127→34│       │         │       │          │
│    │ → 3 suppliers found │       │         │       │          │
├────┼─────────────────────┼───────┼─────────┼───────┼──────────┤
│ 2  │ Jade roller set     │  $3   │  $22    │  73%  │ MEDIUM   │
│    │ → TikTok #guasha 2B │       │         │       │          │
│    │ → Market saturating │       │         │       │          │
│    │ → Differentiate pkg │       │         │       │          │
├────┼─────────────────────┼───────┼─────────┼───────┼──────────┤
│ 3  │ LED face mask       │  $45  │  $149   │  70%  │ HIGH     │
│    │ → Amazon +340% YoY  │       │         │       │          │
│    │ → 14% return rate   │       │         │       │          │
│    │ → High margin, risk │       │         │       │          │
└────┴─────────────────────┴───────┴─────────┴───────┴──────────┘

OV5 insight: "3 of your top 10 audience-overlap creators promoted 
sunscreen sticks in the last 2 weeks. Average engagement: 8.2% — 
above your usual 4.1%. Consider prioritizing."
```

## 4. Business Model

**Flat SaaS, no revenue share.** Creators pay for intelligence, not for revenue processing.

| Tier | Price | What they get |
|------|-------|---------------|
| Free | $0 | 1 product pick/week, basic margin calculator |
| Pro | $49/mo | 5 picks/week, competitor cross-reference, supplier links |
| Scale | $99/mo | Unlimited picks, audience-overlap insights, trend alerts |
| MCN | $499/mo | Multi-creator dashboard, API access, white-label reports |

**Why flat pricing:** Creators trust TikTok with revenue data because TikTok IS the platform. Asking a third-party tool for revenue share requires a trust level that takes years to build. Flat pricing is honest: "We give you intelligence, you make more money, we charge a fixed fee."

**OV5 makes the margins work:** A $49/mo product with $200/mo total OV5 operational cost needs 5 paying users to break even. At $99/mo, 3 users. OV5's experiment loop runs continuously — the matching algorithm gets smarter every day. After 500 experiments, product recommendations are 3× more accurate than week 1. The ontology IS the moat.

## 5. OV5 Development Effort

| Component | Status | Effort |
|-----------|--------|--------|
| GTM Mayor scanning | Production (scans repos) | Low (add product sources) |
| Allium behavioral specs | Production | Low (add product schema) |
| Ontology classification | Production | Low (add `:product-match` category) |
| World Store persistence | Production | Done |
| Clojure business logic | Module skeleton exists | Medium (10-15 .clj files) |
| Datahike queries | Pattern established | Low |
| Dashboard (Reagent) | Not started | Medium |
| Chrome extension | Not started | Medium (overlay creator profile) |
| `clojure.test` coverage | Pattern established | Low (add per module) |

**Total OV5 build effort:** ~80% of code generation from existing infrastructure. The experiment loop, ontology, World Store, GTM Mayor, clojure.test runner, clj-kondo lint, and multi-backend routing are all production-ready. The new work is product-specific data extraction + the dashboard.

## 6. Why This Beats Building From Scratch

| Factor | Build from scratch | OV5-powered |
|--------|-------------------|-------------|
| Data pipeline | Write crawlers from scratch | GTM Mayor already scans external sources |
| Analysis engine | Build classification system | Ontology router already classifies |
| Storage | Set up PostgreSQL/vector DB | Datahike already wired (git-like, immutable) |
| Code improvement | Manual refactoring | 100+ experiments/month autonomously |
| Memory | None (stateless) | Mementum remembers every product analysis |
| Backend routing | Manual API failover | 12-backend auto-failover for LLM calls |
| Tests | Write test infrastructure | clojure.test runner + clj-kondo lint ready |
| Time to launch | 3-6 months | 2-4 weeks (mostly product-specific code) |

## 7. Related Files

- `mementum/knowledge/clojure-first-multiplatform-architecture.md` — Clojure strategy
- `lisp/modules/gptel-auto-workflow-research.el` — GTM Mayor research
- `lisp/modules/gptel-ext-world-store.el` — Datahike bridge
- `BUSINESS_CONTEXT.md` — full business context with demo narrative
