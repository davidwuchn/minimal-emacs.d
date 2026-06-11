---
symbol: 🔁
date: 2026-06-11
---

# syntax-ppss can move point

`syntax-ppss` is not point-neutral inside scan loops. In a `while` around `search-forward`, calling `(syntax-ppss pos)` can move point back to `pos`, so the next search rediscovers the same match and the loop never advances.

Fix: wrap the call in `save-excursion` (or otherwise restore point) before continuing the scan. For the provide-inside-defun audit/fix, `save-excursion` around `(syntax-ppss provide-pos)` was enough.

Rule of thumb: treat parser helpers as potentially point-moving until proven otherwise.
