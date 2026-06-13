# LegalOS — Product Specification

> **AI that knows the law. For lawyers who can't afford Harvey.**

---

## I — Idea

### The Problem

**Solo lawyers and small firms spend 40% of their time on tasks AI could handle — but they can't afford enterprise legal AI.**

A solo attorney with 50 active cases handles everything: document review, legal research, contract drafting, client communication, billing. They bill $200-400/hour but only 60% of their time is billable. The other 40% is research, drafting, and review — tasks that AI can accelerate 3-10×.

The tools today are either too expensive or too generic:
- Harvey: $1K-5K+/seat/month — built for AmLaw 100, not solo firms
- ChatGPT/Claude: generic, no legal domain knowledge, hallucinates citations
- Westlaw/LexisNexis: research only, $300-800/month, no AI features
- Mike (OSS): requires self-hosting Supabase + R2 + multiple API keys

**No affordable, self-improving AI exists for the 1.2 million US lawyers NOT at big firms.**

### Why It Matters

| Signal | Number |
|--------|--------|
| US lawyers | 1.3 million |
| Lawyers at firms <50 attorneys | 75% (975K) |
| Solo practitioners | 400K |
| Average hourly rate | $200-400 |
| Time lost to non-billable research/drafting | 15-25 hours/week |
| Harvey's price (est.) | $1K-5K+/seat/month |
| ChatGPT/Gemini hallucination rate on legal | 15-30% |

This is a **high-frequency, high-cost pain point** for a million professionals with no affordable solution.

### Who Feels This Pain

- **Solo practitioners** (400K in US): doing everything themselves, drowning in documents
- **Small firms** (2-10 lawyers): sharing overhead but can't afford dedicated legal ops
- **Mid-size firms** (10-50): have some tools but nothing AI-native
- **Legal aid organizations**: massive caseloads, zero AI budget
- **Paralegals**: spend days on document review that AI could do in minutes

---

## P — Product

### What LegalOS Does

LegalOS is an AI legal assistant that handles the four highest-time-cost tasks for lawyers:

| Feature | What It Does | Time Saved |
|---------|-------------|------------|
| **Document Review** | Analyzes contracts, briefs, discovery — highlights risks, missing clauses, inconsistencies | 70% |
| **Legal Research** | Searches case law (CourtListener), statutes, regulations — returns cited, verified answers | 60% |
| **Contract Drafting** | Generates first drafts from templates + context — clause suggestions, risk flags | 50% |
| **Case Analysis** | Summarizes case documents, extracts key facts, identifies precedent relationships | 80% |

**No hallucinated citations.** Every legal reference is verified against CourtListener or user-uploaded sources.

### How It Works

1. **Upload** — Drop contracts, briefs, discovery documents (PDF, DOCX, TXT)
2. **Ask** — "Does this contract have a non-compete clause? Is it enforceable in California?"
3. **Research** — "Find cases where California courts invalidated non-competes for software engineers"
4. **Draft** — "Generate an employment agreement with California-compliant non-compete language"
5. **Learn** — OV5 experiments on accuracy, relevance, and completeness — compounds weekly

### Feature Deep-Dive

**Document Review:**
- Clause extraction: identifies 50+ standard contract clauses automatically
- Risk scoring: flags unusual terms, missing protections, jurisdiction-specific issues
- Comparison: side-by-side analysis of two versions of the same document
- Batch processing: analyze 100+ documents simultaneously

**Legal Research:**
- CourtListener integration: 7M+ US court opinions, searchable
- Citation graph: traces precedent relationships (which cases cite which)
- Jurisdiction filter: limit results to specific courts, states, circuits
- Natural language: "cases where non-compete was found unenforceable for lack of consideration"

**Contract Drafting:**
- Template library: 20+ standard agreements (NDA, employment, service, lease)
- Context-aware: adapts clauses based on jurisdiction, industry, party type
- Clause library: reusable clause snippets with jurisdiction notes
- Redline generation: produces track-changes output for existing contracts

**Case Analysis:**
- Auto-summarization: extracts parties, claims, defenses, key dates
- Issue spotting: identifies legal issues from complaint language
- Timeline generation: creates visual case timelines from document dates
- Precedent mapping: shows how cited cases relate to current matter

---

## O — Opportunity

### Market: Solo + Small Firm Lawyers

| Segment | Count (US) | AI Need | Price Sensitivity |
|---------|-----------|---------|-------------------|
| Solo practitioners | 400K | High (doing everything alone) | High |
| Small firms (2-10) | 350K | High (no dedicated ops) | Medium |
| Mid-size (11-50) | 150K | Medium (some tools) | Medium |
| Legal aid | 80K | Very high (massive caseloads) | Low |
| **Total addressable** | **~1M** | | |

### Why This Market

1. **Harvey serves the top 5%** — AmLaw 100, Fortune 500. The other 95% have no AI.
2. **Mike proves demand** — 3.7K GitHub stars for an OSS legal AI platform
3. **CourtListener is free** — 7M+ US court opinions, no API cost for bulk data
4. **Lawyers bill by the hour** — if AI saves 10 hours/week at $300/hr, that's $3K/week value
5. **Regulatory tailwind** — courts increasingly expect AI-assisted research efficiency

### Competitor Positioning

| | Harvey | Mike | Westlaw/Lexis | ChatGPT | **LegalOS** |
|---|---|---|---|---|---|
| Price | $1K-5K+/mo | Free (OSS) | $300-800/mo | $20/mo | **$49-199/mo** |
| Legal-specific | ✅ | ✅ | ✅ | ❌ | ✅ |
| Document review | ✅ | ❌ | ❌ | ❌ | ✅ |
| Case law search | ✅ | ✅ | ✅ | ❌ | ✅ |
| Contract drafting | ✅ | ❌ | ❌ | Partial | ✅ |
| Self-improving | ❌ | ❌ | ❌ | ❌ | ✅ |
| Verifiable citations | ✅ | ✅ | ✅ | ❌ | ✅ |
| Open source | ❌ | ✅ | ❌ | ❌ | ✅ |

---

## P — Plan

### Business Model

**Flat SaaS. No per-document pricing. No revenue share.**

| Tier | Monthly Price | Who | What |
|------|--------------|-----|------|
| Free | $0 | Law students, legal aid | 5 document reviews/mo, 10 research queries/mo |
| Solo | $49/mo | Solo practitioners | 50 reviews/mo, unlimited research, 20 drafts/mo |
| Firm | $149/mo | Firms 2-10 | 200 reviews/mo, unlimited research, 100 drafts/mo, team sharing |
| Pro | $299/mo | Firms 11-50 | Unlimited everything, priority support, API access |

### Unit Economics

| | Solo | Firm |
|---|---|---|
| Revenue/user/month | $49 | $149 |
| Operating cost/user/month | ~$5 | ~$8 |
| Gross margin | 90% | 95% |
| Break-even users | 5 Solo | 2 Firm |

### Revenue Projection

| Month | Users | Revenue | Milestone |
|-------|-------|---------|-----------|
| 1 | 50 | $2,450 | Beta launch |
| 3 | 200 | $9,800 | PMF validation |
| 6 | 500 | $24,500 | Growth |
| 12 | 1,500 | $73,500 | Self-sustaining |
| 24 | 5,000 | $245,000 | Market leader |

---

## GTM Strategy

### Phase 1: Legal Aid + Law Schools (Months 1-3)

**Goal:** 200 active users, zero revenue. Build trust and case studies.

**Why:** Legal aid has massive need, zero budget. Law students will become paying lawyers. Free users provide feedback and testimonials.

**Channels:**
- Legal aid organization partnerships (free access)
- Law school clinics (free for educational use)
- Bar association newsletters and events

### Phase 2: Solo Practitioners (Months 4-8)

**Goal:** 500 paying users at $49/mo.

**Channels:**
- Solo/small firm Facebook groups and Reddit (r/LawFirm, r/Lawyertalk)
- State bar association CLE (Continuing Legal Education) presentations
- Content marketing: "I let AI review my contracts for 30 days — here's what it found"
- SEO: "AI contract review for solo attorneys" "affordable legal AI"

### Phase 3: Small Firms (Months 9-12)

**Goal:** 1,500 paying users, $50-75K MRR.

**Channels:**
- Firm referrals (partners bring in associates)
- Legal tech conferences (ABA Techshow, Legalweek)
- Integration partnerships (Clio, MyCase, PracticePanther)
- Direct sales to small firm managing partners

### PMF Signals

| Signal | Target |
|--------|--------|
| Free → Paid conversion | >25% |
| Month-2 retention | >70% |
| Referral rate | >20% of new users |
| Time saved per lawyer/week | >5 hours |
| Citation accuracy | >95% |
| NPS (Net Promoter Score) | >40 |

---

## International Expansion Plan

LegalOS rolls out in waves, each building on the last. Common law markets first (same engine), civil law markets next (adapted engine), then emerging markets (localized engine).

### Wave 1: US (Month 1-4) — Prove the Model

| | US |
|---|---|
| Legal system | Common law |
| Lawyers | 1.3M |
| Case law source | CourtListener (7M+ opinions, free) |
| Language | English |
| GTM | Bar associations, solo practitioner groups, legal aid |
| Price | $49-299/mo |
| Revenue target (Month 4) | 200 users, $10K/mo |

**Why first:** Largest English-speaking market. CourtListener is free. Contract types are standardized. PMF proven here before expanding.

### Wave 2: UK + Commonwealth (Month 5-7) — Same Language, Same Law

| | UK | Canada | Australia | New Zealand |
|---|---|---|---|---|
| Legal system | Common law | Common law (QC civil) | Common law | Common law |
| Lawyers | 200K | 130K | 90K | 15K |
| Case law | BAILII (free) | CanLII (free) | AustLII (free) | NZLII (free) |
| Language | English | English/French | English | English |
| Price | £39-239/mo | C$59-359/mo | A$69-399/mo | NZ$69-399/mo |

**Why second:** Same legal system. Same language. Free case law databases (BAILII/CanLII/AustLII — all part of the Free Access to Law Movement). Near-zero engine adaptation. Combined: 435K lawyers.

### Wave 3: EU (Month 8-11) — Civil Law, GDPR Ready

| | Germany | France | Netherlands | Nordics |
|---|---|---|---|---|
| Legal system | Civil law | Civil law | Civil law | Civil law |
| Lawyers | 165K | 70K | 18K | 25K |
| Case law | Bundesgerichtshof | Legifrance | Rechtspraak.nl | National courts |
| Language | German | French | Dutch | SV/DK/NO/FI |
| GDPR | ✅ Required | ✅ Required | ✅ Required | ✅ Required |
| Price | €39-239/mo | €39-239/mo | €39-239/mo | €39-239/mo |

**Why third:** Largest civil law market. GDPR compliance is mandatory but OV5 can self-host per country. Statute databases are public. Combined: 280K+ lawyers. Localization needed per language.

### Wave 4: China (Month 12-15) — Largest Untapped Market

| | China |
|---|---|
| Legal system | Civil law (socialist) |
| Lawyers | 750K+ |
| Case law | 中国裁判文书网 (130M+ opinions, public) |
| Statutes | 全国人大法规数据库 |
| Database partner | 北大法宝 (PKULaw) |
| Language | Chinese |
| Distribution | WeChat Mini Program |
| Price | ¥99-599/mo ($14-82) |
| Revenue target (Month 15) | 5,000 users, ¥495K/mo ($68K) |

**Why fourth:** Builds on civil law adaptations from Wave 3. Massive market with zero AI legal competition. WeChat distribution eliminates app-install friction. Government mandates digital legal transformation.

### Wave 5: Emerging Markets (Month 16-24)

| | India | Brazil | Southeast Asia | Africa |
|---|---|---|---|---|
| Legal system | Common law | Civil law | Mixed | Mixed |
| Lawyers | 1.5M+ | 1.2M+ | 200K+ | 300K+ |
| Case law | Indian Kanoon | JusBrasil | National courts | AfricanLII |
| Language | English | Portuguese | EN/TH/VN/ID | EN/FR/PT |
| Price | ₹499-2,499/mo | R$49-249/mo | $9-49/mo | $9-29/mo |

**Why last:** Largest total lawyer population (3.2M+). Very price-sensitive — needs ultra-low pricing. Indian Kanoon and AfricanLII provide free case law. Combined: 3.2M+ lawyers. Revenue from volume, not per-user.

### International Rollout Timeline

```
Month 1-4  │ US           ████████░░ 200 users, $10K/mo
Month 5-7  │ Commonwealth ░░░░████░░ 435K lawyers addressable
Month 8-11 │ EU           ░░░░░░██░░ 280K lawyers, GDPR
Month 12-15│ China        ░░░░░░░░██ 750K lawyers, WeChat
Month 16-24│ Emerging     ░░░░░░░░░█ 3.2M lawyers, volume play
```

### Revenue by Wave (Month 24 Projection)

| Wave | Users | Avg Price | Monthly Revenue | Share |
|------|-------|-----------|-----------------|-------|
| US | 1,500 | $49 | $73,500 | 28% |
| Commonwealth | 800 | £39 ($49) | $39,200 | 15% |
| EU | 600 | €39 ($42) | $25,200 | 10% |
| China | 5,000 | ¥99 ($14) | $70,000 | 27% |
| Emerging | 12,000 | $9 | $108,000 | 42% |
| **Total** | **19,900** | | **$315,900** | |

**Emerging markets drive volume. US/UK drive revenue per user. China bridges both.**

### What Changes Per Market

| Layer | What Adapts | Effort |
|-------|------------|--------|
| Case law source | New API/parser per country | ~1 .clj file |
| Statute database | New API/parser | ~1 .clj file |
| Contract templates | Jurisdiction-specific clauses | ~1 .clj file |
| Language | Translation layer (AI-assisted) | ~2 .clj files |
| Pricing | Country config | 1-line change |
| GTM | Local partnerships | Non-code |
| Regulatory | GDPR, data residency | Infrastructure |

**OV5 learns cross-market patterns.** A contract clause flagged in Germany can inform reviews in France. A citation pattern from UK common law can improve US research. The ontology compounds globally.

---

## T — Team

### Who Builds This

LegalOS is built and operated by OV5 — the self-improving AI system that runs experiments, learns from outcomes, and compounds knowledge. One person oversees direction. The system handles execution.

### What OV5 Replaces

| Role | Traditional | LegalOS (OV5) |
|------|------------|---------------|
| Backend engineer | $150K/yr | $0 |
| Frontend engineer | $130K/yr | $0 |
| ML/legal domain expert | $200K/yr | $0 (CourtListener + OV5 ontology) |
| DevOps | $130K/yr | $0 |
| Total saved | $610K/yr | $200/mo flat |

### What the Human Does

15 minutes/day: review kept experiments, approve high-risk proposals, set strategic direction. Everything else is automated.

---

## M — Milestones

### Completed

| Milestone | When | Evidence |
|-----------|------|----------|
| Product spec | June 2026 | This document |
| OV5 engine (shared infra) | June 2026 | CreatorOS modules (31 tests, 0 failures) |
| Clojure toolchain | June 2026 | test/lint/format/fix, CI-ready |
| CourtListener API feasibility | June 2026 | Verified: 7M+ opinions, free bulk data |

### Next

| Milestone | Target | Dependencies |
|-----------|--------|-------------|
| Document parser (PDF, DOCX) | Month 1 | LibreOffice CLI + BB wrapper |
| CourtListener search module | Month 1 | `src/legalos/case_search.clj` |
| Contract clause extraction | Month 2 | `src/legalos/doc_analysis.clj` |
| Legal research engine | Month 2 | `src/legalos/legal_research.clj` |
| 10 legal aid beta partners | Month 2 | Working prototype |
| 50 law student users | Month 3 | Law school partnerships |
| First paying solo customer | Month 4 | Payment integration |
| 500 paying users | Month 8 | Content marketing flywheel |
| $50K MRR | Month 12 | Category leadership |

---

## Self-Regulation (5-Layer)

| Layer | LegalOS Owns | OV5 Enables |
|-------|-------------|-------------|
| **Sensor** | Document accuracy, citation verification rate, user feedback | OV5 monitoring + CourtListener API health |
| **Policy** | Citation confidence thresholds, jurisdiction-specific rules | Experiment config |
| **Tools** | Document parsing, clause extraction, case search, drafting | clojure.test, clj-kondo, zprint |
| **Quality Gate** | 3 gates: lint → format → test. No hallucinated citations. | `scripts/run-tests.sh` |
| **Learning** | Keep-rate on document analysis accuracy, citation relevance | 100+ experiments/month compounds accuracy |

---

## Architecture: One Engine, Five Products

```
                        ┌──────────────────────────────────────┐
                        │         OV5 SHARED ENGINE            │
                        │  GTM Mayor │ Ontology │ World Store  │
                        │  Experiment Loop │ 12 Backends       │
                        └──┬────────┬────────┬────────┬───────┘
                           │        │        │        │
            ┌──────────────▼┐ ┌─────▼────┐ ┌▼─────────▼┐ ┌────▼──────────┐
            │  CREATOROS    │ │ SEEDSIGHT│ │  AMAZON   │ │   LEGALOS     │
            │  TikTok B2C   │ │ RedNote  │ │  Seller   │ │   Legal B2C   │
            │  $19-99/mo    │ │ $530-4K  │ │ $49-99/mo │ │  $49-299/mo   │
            └───────────────┘ └──────────┘ └───────────┘ └───────────────┘
```

**One engine. One language. Five products. Zero additional infrastructure cost.**

---

## Why This Wins

1. **No competition in the niche.** Harvey owns enterprise. Mike is self-host OSS. No one serves solo/small firms with affordable AI.
2. **CourtListener is free.** 7M+ US opinions, bulk data available. Zero API cost.
3. **Lawyers bill by the hour.** 10 hours saved/week at $300/hr = $3K/week value. $49/mo is trivial.
4. **Self-improving moat.** Every document review, every research query, every drafted contract feeds the ontology. After 500 experiments, LegalOS knows more about your practice area than any paralegal.
5. **OV5 makes it possible.** $200/mo total ops cost. 90%+ margins from day one.
6. **Five products from one engine.** Same infrastructure powers CreatorOS, SeedSight, Amazon Seller, and LegalOS. Each new product costs near-zero to add.
