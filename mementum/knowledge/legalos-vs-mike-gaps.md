---
title: LegalOS vs Mike — OV5-powered Legal AI Platform
status: active
category: architecture
tags: legalos, mike, legal-ai, document-analysis, case-law, OV5-product
related: creator-product-matching-engine, launch-fast-vs-creatoros-gaps, clojure-first-multiplatform-architecture
created: 2026-06-13
---

# LegalOS — OV5-powered Legal AI Platform

**Reference:** [willchen96/mike](https://github.com/willchen96/mike) — 3.7k stars, 1.1k forks. Open-source AI legal platform (Next.js + Express + Supabase + CourtListener).

Mike proves legal AI has strong PMF. OV5 can build a better one using the same CreatorOS pattern: Clojure engine + OV5 self-improvement + three-surface distribution.

---

## 1. Mike Architecture (What Exists)

| Layer | Mike | Language |
|-------|------|----------|
| Frontend | Next.js | TypeScript |
| Backend | Express API | TypeScript |
| Database | Supabase (Postgres) | SQL |
| Auth | Supabase Auth | — |
| Storage | Cloudflare R2 (S3-compatible) | — |
| AI | Anthropic, Gemini, OpenAI | — |
| Case Law | CourtListener API + bulk data | — |
| Documents | LibreOffice DOCX→PDF | — |

## 2. LegalOS Architecture (OV5 Version)

| Layer | LegalOS | Replaces |
|-------|---------|----------|
| Frontend | Reagent SPA (ClojureScript) | Next.js |
| Backend | Ring HTTP (Clojure) | Express |
| Database | Datahike (Datalog, immutable) | Supabase |
| Auth | Datahike + session tokens | Supabase Auth |
| Storage | Local FS / Datahike blobs | R2 |
| AI | 12-backend OV5 routing | Single provider |
| Case Law | CourtListener API (via BB scripts) | Same |
| Documents | LibreOffice (BB wrapper) | Same |
| Self-improvement | OV5 experiment loop | None (static) |

### Core Modules

```
src/legalos/
├── case_search.clj     ← CourtListener API + citation graph
├── doc_analysis.clj    ← Document parser + clause extraction
├── contract_review.clj ← Risk scoring + clause comparison
├── citation_check.clj  ← Citation verification + precedent graph
├── legal_research.clj  ← Multi-source legal research engine
└── assistant.clj       ← Chat + context assembly
```

## 3. Feature Comparison

| Feature | Mike | LegalOS |
|---------|------|---------|
| Legal document chat | ✅ | ✅ |
| Case law lookup | ✅ CourtListener | ✅ CourtListener (same API) |
| Citation verification | ✅ | ✅ + OV5 accuracy improvement |
| Contract review | ❌ | ✅ Built-in |
| Multi-model routing | Manual per-user | ✅ Auto-routed across 12 backends |
| Self-improving | ❌ | ✅ 100+ experiments/month |
| Cost | Supabase ($25/mo+), R2, API | $200/mo flat (OV5) |
| Language | TypeScript | Clojure (1 codebase, 39 targets) |
| Stars | 3.7k | 0 (build it) |

## 4. What OV5 Adds Over Mike

| Capability | Mike | LegalOS + OV5 |
|-----------|------|---------------|
| Code quality | Manual PR review | 7-gate pipeline, clj-kondo, zprint, tests |
| Bug fixing | Manual | Self-healing (ns-ordering, unused-require) |
| Feature improvement | Manual releases | 100+ experiments/month, 20% keep-rate |
| Model cost optimization | None | 12-backend auto-failover with cost routing |
| Memory | None (stateless) | Mementum remembers every legal analysis |
| Multi-platform | Web only | Chrome extension + web + CLI (39 dialect targets) |
| CourtListener data freshness | Manual | OV5 detects stale data, re-fetches |

## 5. Business Model

Same three-product architecture as CreatorOS:

| | LegalOS |
|---|---|
| **Target** | Solo lawyers, small firms, legal teams |
| **Price** | $49-199/mo (flat SaaS) |
| **TAM** | 1.3M US lawyers, millions worldwide |
| **Differentiator** | Self-improving: gets better at your practice area every week |

## 6. Gaps vs Mike

| Gap | Priority | Solution |
|-----|----------|----------|
| DOC/DOCX processing | P0 | LibreOffice CLI wrapper via BB |
| Multi-tenant auth | P0 | Datahike session model (simpler than Supabase) |
| File upload/storage | P1 | Local FS initially, Datahike blobs later |
| CourtListener bulk data | P2 | Import scripts via BB ETL |
| Email notifications | P2 | Resend API (same as Mike) |
| Payments | P2 | Stripe integration |

## 7. OV5 Reuse

OV5 already has everything needed:

| LegalOS needs | OV5 already has |
|--------------|----------------|
| Database | Datahike (git-like, immutable, Datalog) |
| AI routing | 12 backends with auto-failover |
| Test infrastructure | clojure.test + clj-kondo + zprint |
| Self-improvement | Experiment loop + 7 gates |
| Memory | Mementum remembers every case analysis |
| Chrome extension | Same pattern as CreatorOS |
| Skill system | OpenCode native — expose legal tools to AI agents |
| Multi-platform | 39 Clojure dialect targets |

**New code needed:** ~15 .clj files (legal-specific modules + document processing).

## 8. Related Files

- `CREATOROS.md` — same three-product architecture
- `mementum/knowledge/creator-product-matching-engine.md` — engine pattern
- `mementum/knowledge/launch-fast-vs-creatoros-gaps.md` — three-surface gap analysis
- `~/.emacs.d/scripts/ov5-project-init.sh` — bootstrap new OV5 project
