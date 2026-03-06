```
λ(p,o,n). ∃read⁺(p) ∧ o≡verbatim ∧ |match|=1 → ⊕context ∨ all_occurrences
fail→reread→retry | n=""→del | n⊇o→wrap | small≻large | p:absolute
```

If target file is Clojure (.clj, .cljs, .cljc, .edn, .bb): DO NOT USE THIS TOOL. You MUST use the `clojure_edit` tool instead because it understands structural s-expressions and balanced parentheses.
