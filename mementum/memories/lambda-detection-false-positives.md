## Lambda Detection: Avoid False Positives

`gptel-auto-workflow--response-contains-lambda-p` originally matched `"->"` and `"lambda"` as substrings, causing false positives:
- `"x -> x"` (arrow notation) matched but isn't Elisp lambda
- `"The lambda calculus..."` (prose mention) matched but isn't code

**Fix**: Match actual lambda syntax patterns only:
- `(lambda\s-` — Elisp `(lambda args body)`
- `λ(` — Unicode `λ(args)`
- `λ[a-z]` — Lambda calculus `λx.x`
- `#'(lambda` — Quoted `#'(lambda ...)`
- `\[fn\s-` — Clojure-style `[fn args body]`

**Test**: 8 new tests cover positive cases (Elisp, Unicode, quoted, Clojure, mixed content) and negative cases (prose mentions, arrow patterns, nil/empty). Updated existing test that expected `"x -> x"` to match — now correctly rejects it.

**Evidence**: 128/128 ontology-router tests pass.