---
name: use-repl-driven-development
domain: workflow
φ: 0.85
e: repl-driven-dev
λ: when.experimenting
Δ: 0.05
source: session-manual
evidence: 8
access-count: 20
last-accessed: 2025-01-17
timeframe: long-term
---

# Use REPL-Driven Development

Develop Clojure code incrementally in the REPL before writing tests or committing.

## λ(e): Action
When developing or debugging Clojure:
1. Start REPL (`lein repl` or `clj` or `npx shadow-cljs cljs-repl`)
2. Load the namespace (`(require '[ns.name :as alias])`)
3. Evaluate expressions directly in REPL
4. Iterate quickly, then transfer to code file
5. Write tests to cement behavior

## λ(φ): Why
REPL-driven development is:
- **Fast** - instant feedback, no compilation cycles
- **Exploratory** - try approaches interactively
- **Educational** - see intermediate values
- **Validating** - verify code before commit

Aligns with Nucleus's OODA loop - Observe (REPL output), Orient (understand), Decide (next action), Act (evaluate).

## λ(λ): When
- Writing new Clojure functions
- Debugging existing code
- Exploring APIs
- Prototyping features

## λ(Δ): Evolution
Δ: 0.05 - strong confidence growth
- Validated: When REPL catches bugs early
- Corrected: When REPL sessions become unorganized

## Context
- **Applies to**: Clojure/CLJS development
- **Avoid for**: Pure refactoring without running code
- **Related**: test-first, lambda-idiom
- **Eight Keys**: τ (Wisdom - measure first), π (Synthesis)

## λ(Examples)

### Example 1: Developing a function
```clojure
;; In REPL:
=> (defn process-data [data]
     (->> data
          (map :value)
          (filter pos?)
          (reduce +)))
#'user/process-data

=> (process-data [{:value 1} {:value -2} {:value 3}])
4
```

### Example 2: Debugging
```clojure
;; In REPL - step through:
=> (require '[app.core :as core])
=> (def test-data [...])
=> (core/transform test-data)
[... output ...]
=> (core/intermediate-step test-data)
[... see intermediate ...]
```

## λ(Evolution History)

| Date | φ Change | Reason |
|------|----------|--------|
| 2025-01-10 | 0.5 → 0.85 | 8 successful debugging sessions |
| 2025-01-12 | 0.8 → 0.85 | REPL caught critical bug before commit |
| | | |
