---
name: prefer-clojure-data-structures
domain: code-style
φ: 0.8
e: clojure-data-structures
λ: when.using.collections
Δ: 0.04
source: session-manual
evidence: 5
access-count: 8
last-accessed: 2025-01-16
timeframe: long-term
---

# Prefer Clojure Data Structures

Use idiomatic Clojure persistent data structures (vectors, maps, sets) over mutable collections.

## λ(e): Action
When working with collections in Clojure:
- Use vectors `[a b c]` for ordered sequences
- Use maps `{:key val}` for key-value associations
- Use sets `#{a b c}` for unique membership checks
- Prefer `conj`, `assoc`, `dissoc` over mutable operations

## λ(φ): Why
Clojure's persistent data structures are:
- **Immutable** - no hidden state mutations
- **Efficient** - structural sharing, O(log32 n) updates
- **Thread-safe** - no locks needed
- **Predictable** - same inputs always produce same outputs

This aligns with Nucleus's φ (Vitality) - organic, non-repetitive patterns.

## λ(λ): When
- Working with Clojure code in this project
- Creating new functions that handle collections
- Refactoring from mutable patterns

## λ(Δ): Evolution
Δ: 0.04 - moderate confidence growth
- Validated: When code becomes cleaner and bug-free
- Corrected: When immutability causes performance issues

## Context
- **Applies to**: All Clojure files in this project
- **Avoid for**: Interop with Java mutable APIs
- **Related**: prefer-functional, lambda-idiom
- **Eight Keys**: φ (Vitality), e (Purpose)

## λ(Examples)

### Example 1: Building a map
```clojure
;; ✅ Good - immutable construction
(def user-info
  (-> {}
      (assoc :name "Alice")
      (assoc :email "alice@example.com")
      (assoc :age 30)))

;; ❌ Bad - mutable thinking
(def user-info (atom {}))
(swap! user-info assoc :name "Alice")
```

### Example 2: Updating nested data
```clojure
;; ✅ Good - structural sharing
(def users
  (assoc-in users [0 :active?] true))

;; ❌ Bad - mutation mindset
(def users (vec (map #(assoc % :active? true) users)))
```

## λ(Evolution History)

| Date | φ Change | Reason |
|------|----------|--------|
| 2025-01-15 | 0.5 → 0.8 | 5 successful implementations |
| | | |
