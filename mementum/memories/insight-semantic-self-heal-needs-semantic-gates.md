## Insight

`defvar` default rewrites can pass byte-compile/load gates and still be wrong.

The nil-hash self-heal bug showed that OV5 needs behavior-specific gates for semantic fixers:
- exact table-argument matching instead of loose hash-function regexes
- buffer-aware lazy-init detection for multi-binding `setq`
- regression tests on the real affected files

Rule of thumb: if a fixer changes initialization semantics, a loadable file is not enough proof.
