# Mike → LegalOS: OV5 Legal AI Pattern

**Context:** Studied [willchen96/mike](https://github.com/willchen96/mike) — 3.7k star open-source legal AI platform. Same pattern as CreatorOS: domain-specific AI tool with web frontend, backend API, and document processing.

**Key insight:** Mike validates PMF for legal AI. OV5 can build LegalOS using the exact same CreatorOS engine pattern — Clojure modules + Datahike + 12-backend routing + OV5 experiment loop. 80% of infrastructure is shared. The only new code is legal-specific modules (~15 .clj files: case search, document analysis, contract review, citation check, legal research, assistant).

**OV5 advantage over Mike:** Self-improving (experiments compound accuracy), multi-model auto-routing (12 backends vs 3), git-immutable database (Datahike vs Supabase), 7-gate quality pipeline, self-healing code.

**Full analysis:** `mementum/knowledge/legalos-vs-mike-gaps.md`

**Symbol:** 💡
