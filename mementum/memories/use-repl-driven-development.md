---
title: Use REPL-Driven Development
φ: 0.85
e: repl-driven-dev
λ: when.experimenting
Δ: 0.05
evidence: 8
---

💡 REPL-driven development for Clojure: fast feedback, exploratory, validates before commit.

## Action
1. Start REPL (`lein repl` / `clj` / `npx shadow-cljs cljs-repl`)
2. Load namespace: `(require '[ns.name :as alias])`
3. Evaluate expressions directly
4. Iterate, then transfer to code
5. Write tests to cement behavior

## When
- Writing new Clojure functions
- Debugging existing code
- Exploring APIs
- Prototyping features

## Why
- **Fast** - instant feedback
- **Exploratory** - try approaches interactively
- **Educational** - see intermediate values
- **Validating** - verify before commit

## Context
- Applies to: Clojure/CLJS development
- Avoid for: Pure refactoring without running code
- Related: test-first, lambda-idiom