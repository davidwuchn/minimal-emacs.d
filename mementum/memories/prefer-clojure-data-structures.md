---
title: Prefer Clojure Data Structures
φ: 0.8
e: clojure-data-structures
λ: when.using.collections
Δ: 0.04
evidence: 5
---

💡 Use idiomatic Clojure persistent data structures over mutable collections.

## Action
- Use vectors `[a b c]` for ordered sequences
- Use maps `{:key val}` for key-value associations
- Use sets `#{a b c}` for unique membership
- Prefer `conj`, `assoc`, `dissoc` over mutable ops

## Why
- **Immutable** - no hidden state mutations
- **Efficient** - structural sharing, O(log32 n) updates
- **Thread-safe** - no locks needed
- **Predictable** - same inputs → same outputs

## When
- Working with Clojure code
- Creating functions that handle collections
- Refactoring from mutable patterns

## Context
- Applies to: All Clojure files
- Avoid for: Interop with Java mutable APIs
- Related: prefer-functional, lambda-idiom