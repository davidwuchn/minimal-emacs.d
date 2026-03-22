---
title: Clojure Protocol
status: active
category: protocol
tags: [clojure, repl, functional, idioms]
related: [mementum/memories/use-repl-driven-development.md, mementum/memories/prefer-clojure-data-structures.md]
instincts:
  repl-first:
    φ: 0.83
    eight-keys:
      vitality: 0.85
      clarity: 0.78
      purpose: 0.82
      wisdom: 0.75
      synthesis: 0.80
      directness: 0.88
      truth: 0.90
      vigilance: 0.83
    evidence: 5
    last-tested: 2026-03-22
    last-updated: 2026-03-22
  functional:
    φ: 0.80
    eight-keys:
      vitality: 0.82
      clarity: 0.75
      purpose: 0.78
      wisdom: 0.80
      synthesis: 0.82
      directness: 0.85
      truth: 0.78
      vigilance: 0.80
    evidence: 4
    last-tested: 2026-03-20
    last-updated: 2026-03-22
  immutable:
    φ: 0.78
    eight-keys:
      vitality: 0.80
      clarity: 0.72
      purpose: 0.75
      wisdom: 0.78
      synthesis: 0.80
      directness: 0.82
      truth: 0.76
      vigilance: 0.78
    evidence: 3
    last-tested: 2026-03-18
    last-updated: 2026-03-22
  threading:
    φ: 0.80
    eight-keys:
      vitality: 0.82
      clarity: 0.78
      purpose: 0.80
      wisdom: 0.78
      synthesis: 0.82
      directness: 0.80
      truth: 0.80
      vigilance: 0.80
    evidence: 4
    last-tested: 2026-03-19
    last-updated: 2026-03-22
  edge-cases:
    φ: 0.75
    eight-keys:
      vitality: 0.78
      clarity: 0.70
      purpose: 0.75
      wisdom: 0.72
      synthesis: 0.78
      directness: 0.80
      truth: 0.75
      vigilance: 0.72
    evidence: 3
    last-tested: 2026-03-17
    last-updated: 2026-03-22
---

# Clojure Protocol

REPL-first development and idiomatic functional programming patterns.

## Core Principle

**REPL-first, test-driven development** is non-negotiable. Every function must be verified in the REPL before being saved to file.

```
λ(task).write ⟺ [
  read_source(),
  verify_current_behavior(),
  develop_in_REPL(),
  test_edge_cases(nil, empty, invalid),
  save_to_file()
]
```

**Never**: Edit file → hope it works → run tests.
**Always**: REPL → verify → save.

## REPL-First Workflow

1. **Read entire file** - Understand current implementation
2. **Require with reload** - Get latest changes
3. **Test current behavior** - Baseline before modifying
4. **Develop in REPL** - Iterate on solution
5. **Test all edge cases** - nil, empty, invalid inputs
6. **Verify in REPL** - Ensure correctness
7. **Save to file** - Only after verification

## Edge Cases to Test

| Input Type | Edge Cases |
|-------------|-------------|
| Collections | `nil`, `[]`, `'()`, `[1 2]` |
| Numbers | `0`, negative, very large, decimal |
| Strings | `""`, whitespace, unicode |
| Maps | `{}`, empty values, missing keys |
| Keywords/Symbols | `nil`, unknown keys |

## Idiomatic Patterns

### Threading (Prefer Over Nesting)

```clojure
(-> user
    (assoc :login (Instant/now))
    (update :count inc))

(->> users
     (filter active?)
     (map :email))

(some-> user :address :code (subs 0 5))  ; short-circuit nil
```

### Control Flow

```clojure
(when (valid? data)           ; single branch + side effects
  (process data))

(cond                         ; multiple conditions
  (< n 0) :negative
  (= n 0) :zero
  :else   :positive)

(case op                      ; constant dispatch
  :add (+ a b)
  :sub (- a b))
```

### Data & Functions

```clojure
;; Destructuring with defaults
(defn connect [{:keys [host port] :or {port 8080}}])

;; Into for transformations
(into [] (filter even?) nums)

;; Ex-info for structured errors
(throw (ex-info "Not found" {:id user-id}))
```

## Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Functions | kebab-case | `calculate-total` |
| Predicates | `?` suffix | `valid?` |
| Conversions | `src->dst` | `map->vector` |
| Dynamic | `*earmuffs*` | `*connection*` |
| Private | `-` prefix | `-parse-date` |

**NEVER use `!` suffix** - not idiomatic.

## Anti-Patterns

| Instead of... | Use... |
|---------------|--------|
| Atoms for accumulation | `reduce` |
| Nested null checks | `some->` |
| `(! suffix)` | Remove it |
| String keys | Keywords `:key` |
| Explicit recursion | Higher-order functions |
| `println` debugging | REPL evaluation |

### Wisdom Patterns (τ)

**Threading Macro Selection:**
- Use `->` when threading as first argument: `(-> x f1 f2 f3)`
- Use `->>` when threading as last argument: `(->> coll (filter pred) (map f))`
- Use `some->` when nil should short-circuit
- Use `cond->` when conditional threading needed

**Function Selection:**
```clojure
;; Collection empty check
(empty? coll)      ; works on all collections
(seq coll)         ; returns nil if empty (truthy check)

;; First element access
(first coll)       ; safe, returns nil on empty
(peek coll)        ; O(1) for vectors/queues
(nth coll 0)       ; throws on out of bounds
```

### Anti-Pattern → Idiomatic Table

| Anti-Pattern | Idiomatic Replacement |
|--------------|----------------------|
| `(atom [])` + `swap!` | `(reduce f init coll)` |
| `(f3 (f2 (f1 x)))` | `(-> x f1 f2 f3)` |
| `(if (not (nil? x))` | `(when-some [x x]` |
| `(get m :key)` | `(:key m)` |
| `(.length s)` | `(count s)` |

## Verification Gates (Pre-Save)

- [ ] Tested in REPL (happy path + nil/empty/invalid)
- [ ] Threading macros over deep nesting
- [ ] No `!` suffix in names
- [ ] Standard aliases (`str`, `set`, `io`)
- [ ] Zero compilation warnings

## The Three Questions (Pre-Implementation)

1. **Intentions?** - What behavior, not how. Test the what.
2. **Why this approach?** - Challenge: need Component? Or plain functions?
3. **Simpler way?** - Protocol for single impl? Macro when function works?