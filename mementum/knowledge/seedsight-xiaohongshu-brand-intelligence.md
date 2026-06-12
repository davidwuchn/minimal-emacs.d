---
title: SeedSight — OV5-Powered Brand Intelligence for 小红书
status: active
category: architecture
tags: xiaohongshu, rednote, brand-intelligence, zhongcao, B2B, GTM-mayor
related: creator-product-matching-engine, clojure-first-multiplatform-architecture, gptel-auto-workflow-research
created: 2026-06-12
depends-on: clojure-first-multiplatform-architecture
---

# SeedSight — Brand Intelligence for 小红书

**Problem:** Brands spend millions on 小红书 KOL campaigns but have no systematic way to know what's being 种草'd, who's driving the narrative, and whether their category share-of-voice is growing or shrinking.

**Solution:** OV5's GTM Mayor + ontology is a 种草 intelligence engine. Scan 小红书 public content, extract product mentions/sentiment/brand associations, track 种草 velocity, map competitive landscape. Sell to brands at B2B price points.

---

## 1. Why 小红书 Is Fundamentally Different from TikTok

| Dimension | TikTok (抖音) | 小红书 (RedNote) |
|-----------|-------------|-----------------|
| **User intent** | Entertainment, discovery | Research, purchase decision |
| **Core behavior** | Scroll, watch, impulse-buy | Search, read reviews, 种草 |
| **Content format** | Short video dominant | Notes (图文) + short video |
| **Demographics** | Broad (all ages) | 70% female, 90% Gen Z, urban |
| **Commerce model** | Live shopping (带货) | 种草 → buy on Taobao/Tmall |
| **Search volume** | Lower intent signal | 600M daily queries (half of Baidu) |
| **Revenue model** | Ads + live commerce | Advertising (brands + KOLs) |
| **Revenue** | ~$100B+ (Douyin) | $3.7B (2023), $500M profit |
| **Target customer** | Creators (sell to followers) | Brands (understand 种草) |

**Key insight:** 小红书 is a **consumer decision search engine**, not an entertainment platform. Users search "best sunscreen for sensitive skin" and read notes before buying — not "watch this funny video and buy this sunscreen." This makes it ideal for **brand intelligence**, not creator tools.

## 2. The Product: 种草雷达 (SeedSight)

A B2B brand intelligence platform. OV5 scans 小红书 public content and answers brand-critical questions:

| Question | What SeedSight does | OV5 component |
|----------|--------------------|---------------|
| "What's being 种草'd in my category?" | Track product mentions, velocity, sentiment across beauty/skincare/fashion/food | GTM Mayor + ontology |
| "Who's talking about my brand vs competitors?" | Share-of-voice analysis, sentiment comparison, KOL attribution | Allium + World Store |
| "Which KOLs are driving purchase intent?" | Rank KOLs by 种草 effectiveness (engagement × audience trust × category fit) | Ontology router |
| "Is a product about to blow up?" | Detect 种草 acceleration — 3+ sigma above baseline mention velocity | Experiment loop |
| "What's my brand health trend?" | Monthly sentiment trajectory, key discussion themes, risk alerts | World Store + monitoring |

### Data Sources — All Public

| Source | What OV5 extracts | Access |
|--------|-------------------|--------|
| 小红书 search results | Product mentions, note count, engagement | Public web |
| 小红书 notes | Content text, images (OCR), brand mentions, sentiment | Public pages |
| 小红书 KOL profiles | Follower count, engagement rate, category, posting cadence | Public profiles |
| Taobao/Tmall | Product pricing, sales rank, review velocity (cross-ref) | Public pages |
| Baidu Index | Brand search volume trajectory | Public API |

### Example Output

```
Category: 精华液 (Serum) — June 2026

┌─────────────────────┬────────┬────────┬────────┬──────────┐
│ Brand               │ 种草   │ Sent   │ MoM    │ Top KOL  │
│                     │ Volume │        │ Change │          │
├─────────────────────┼────────┼────────┼────────┼──────────┤
│ 珀莱雅 (Proya)      │ 12.4K  │ +0.72  │ +18% ↑ │ @美妆小天才│
│ 薇诺娜 (Winona)     │  8.7K  │ +0.68  │ +7%  ↑ │ @敏感肌专家│
│ 修丽可 (SkinCeuticals)│ 6.2K  │ +0.81  │ +24% ↑ │ @成分控   │
│ 欧莱雅 (L'Oréal)    │  5.1K  │ +0.55  │ -3%  ↓ │ @美妆日记  │
│ 兰蔻 (Lancôme)      │  4.8K  │ +0.61  │ -8%  ↓ │ @贵妇护肤  │
└─────────────────────┴────────┴────────┴────────┴──────────┘

Alert: 珀莱雅 "双抗精华" (Dual-Antioxidant Serum) mentions +340% in 2 weeks.
      3 new KOLs with >100K followers posted reviews this week.
      Estimated 种草 reach: 2.8M impressions.
      Risk: LOW (positive sentiment, organic mentions).
```

## 3. Business Model: B2B SaaS, No Revenue Share

| Tier | Price | Who | What |
|------|-------|-----|------|
| **Starter** | ¥3,888/mo (~$530) | Single brand, 1 category | Category tracker, weekly reports |
| **Growth** | ¥8,888/mo (~$1,220) | Multi-brand, 3 categories | KOL discovery, competitor intel, alerts |
| **Enterprise** | ¥28,888/mo (~$3,960) | Agency/MCN, unlimited | White-label, API access, custom categories |

**Why B2B at 10× creator pricing:**
- Brands have budgets. A single 小红书 KOL campaign costs ¥50K-500K. ¥3,888/mo for intelligence to make that spend smarter is trivial.
- 小红书's own revenue is $3.7B — almost entirely from brand advertising. Brands already pay for access. They'll pay more for intelligence.
- No revenue share complexity. No API dependency. No trust barrier. Brands buy market intelligence, not a percentage of their income.

## 4. OV5 Advantage: 80% Built

| What's needed | OV5 already has | Status |
|--------------|----------------|--------|
| External scanning | GTM Mayor (scans repos, papers, web) | Production |
| Content distillation | Allium v3 (behavioral specs from findings) | Production |
| Entity classification | Ontology router (categorizes targets) | Production |
| Structured storage | Datahike World Store (git-like, immutable) | Production |
| Sentiment analysis | 12-backend LLM routing (Claude, GPT, DeepSeek) | Production |
| Trend detection | Experiment loop (detects patterns over time) | Production |
| Memory | Mementum (remembers every analysis) | Production |
| **New code needed** | ~20%: 小红书 content extractor + brand dashboard | ~15 .clj files |

## 5. Roadmap

| Phase | What | OV5 effort | Revenue unlock |
|-------|------|-----------|---------------|
| **1. 种草 Tracker** | Category mention tracking + sentiment | 1-2 weeks | Starter tier |
| **2. KOL Discovery** | Rank KOLs by 种草 effectiveness | 1 week | Growth tier |
| **3. Competitive Intel** | Share-of-voice, brand comparison | 1 week | Growth tier |
| **4. Early Warning** | 种草 acceleration alerts | 1 week | Enterprise |
| **5. Cross-Platform** | Add Douyin, Weibo, Bilibili sources | Ongoing | Enterprise upsell |

## 6. Comparison: TikTok vs 小红书 Product Strategy

| | CreatorOS (TikTok) | SeedSight (小红书) |
|---|---|---|
| **Target** | Creators (B2C) | Brands (B2B) |
| **Price point** | $49-99/mo | $530-3,960/mo |
| **Core value** | "What to promote today" | "Who's winning the 种草 war" |
| **Key metric** | Product margin, supplier reliability | 种草 velocity, share-of-voice |
| **Data sources** | Amazon, Reddit, AliExpress, Google Trends | 小红书 public content, Taobao, Baidu |
| **Revenue potential** | $50K/mo at 500 paying creators | $500K/mo at 100 enterprise brands |
| **Go-to-market** | Influencer marketing, community | Direct sales, industry reports, KOL agency partnerships |

## 7. Related Files

- `mementum/knowledge/creator-product-matching-engine.md` — TikTok creator product strategy
- `mementum/knowledge/clojure-first-multiplatform-architecture.md` — Clojure strategy
- `lisp/modules/gptel-auto-workflow-research.el` — GTM Mayor research
- `lisp/modules/gptel-ext-world-store.el` — Datahike bridge
- `BUSINESS_CONTEXT.md` — full business context
