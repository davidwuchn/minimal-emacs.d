---
title: Dual Mayor Dashboards — PMF + JTBD + GTM
created: 2026-06-03
tags: [dual-mayor, dashboard, PMF, JTBD, GTM]
---

## Dashboards Created

### pmf-dashboard.md
- **Owner**: `pmf-value-stream` daemon (PMF Mayor)
- **Content**: PLG step, experiments today/week, keep rate, backend performance
- **Updated**: After all projects complete in `run-all-projects`

### jtbd-dashboard.md
- **Owner**: `gtm-product-org` daemon (GTM Mayor)
- **Content**: Market segments, competitive landscape, unmet JTBD outcomes
- **Updated**: After research cycle completes

### gtm-dashboard.md
- **Owner**: `gtm-product-org` daemon (GTM Mayor)
- **Content**: JTBD step, cross-functional alignment, strategic recommendations
- **References**: pmf-dashboard.md + jtbd-dashboard.md
- **Updated**: After research cycle completes (calls jtbd update first)

## Update Functions

All in `lisp/modules/gptel-auto-workflow-production.el`:
- `gptel-auto-workflow--update-dashboard` — generic placeholder replacement
- `gptel-auto-workflow--update-pmf-dashboard` — called from `run-all-projects`
- `gptel-auto-workflow--update-jtbd-dashboard` — called from `run-research`
- `gptel-auto-workflow--update-gtm-dashboard` — calls jtbd then updates GTM

## Design Rationale

- **PMF dashboard** = Value Stream metrics (experiments, keep rate, deployment)
- **JTBD dashboard** = Market intelligence (segments, competition, unmet outcomes)
- **GTM dashboard** = Product Organization execution (alignment, decisions, readiness)

GTM references both PMF and JTBD for full context.

## Tests

2149 tests, 2097 expected, 0 unexpected, 52 skipped — all pass.
