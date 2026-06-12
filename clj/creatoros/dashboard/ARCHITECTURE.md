;; creatoros/dashboard/ARCHITECTURE.md — Dashboard architecture following fulcro-facade pattern

# CreatorOS Dashboard Architecture

**Reference:** [fulcro-facade](https://github.com/michaelwhitford/fulcro-facade) — self-building Fulcro RAD app for AI agents.

## Stack

```clojure
;; deps.edn
{:deps {com.fulcrologic/fulcro {:mvn/version "3.7.1"}
        com.wsscode/pathom3 {:mvn/version "2024.1.1-alpha"}
        com.fulcrologic/fulcro-rad {:mvn/version "1.5.11"}
        oliyh/martian {:mvn/version "2.1.18"}}}
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    UI Layer (Fulcro RAD)                 │
│  product-report.cljs  creator-form.cljs  match-grid.cljs│
├─────────────────────────────────────────────────────────┤
│                  Pathom Resolvers                        │
│  :creatoros/matching  :creatoros/scoring  :creatoros/profit │
│                    :creatoros/sources                    │
├─────────────────────────────────────────────────────────┤
│                CreatorOS Engine (shared)                  │
│  matching.clj   scoring.clj   profit.clj   sources.clj  │
├─────────────────────────────────────────────────────────┤
│                Datahike World Store                       │
│  (product entities, creator profiles, match history)     │
└─────────────────────────────────────────────────────────┘
```

## Integration Pattern (per fulcro-facade)

| Step | File | Purpose |
|------|------|---------|
| 1 | `api/creatoros.yml` | OpenAPI spec for matching engine |
| 2 | `api/client.clj` | Martian HTTP client |
| 3 | `model/resolvers.clj` | Pathom resolvers calling engine modules |
| 4 | `ui/reports.clj` | Product match reports, scoring tables |
| 5 | `ui/forms.clj` | Creator profile input, product search |
| 6 | `client.cljs` | Statechart routing + Fulcro entry |

## OV5 Generates This

```bash
# OV5 experiment loop builds dashboard modules
# Each experiment:
#   1. Generates Fulcro component
#   2. Tests via clojure.test
#   3. Lint via clj-kondo
#   4. Format via zprint
#   5. Merge if passes all gates
```

## Run

```bash
# Terminal 1: Build
cd clj/creatoros/dashboard && bb dev

# Terminal 2: API server
cd ~/.emacs.d && bb -m creatoros.api-server
# → http://localhost:8080
```

The dashboard reads from the same Datahike World Store as the CLI demo. Pathom resolvers call `creatoros.matching/match`, `creatoros.scoring/composite-score`, etc. directly within the same Clojure process.
