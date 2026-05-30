## Version-Counter Cache Invalidation Pattern

Use a version counter (integer) instead of `eq` identity comparison for cache invalidation. This handles all mutation patterns:

- **`eq` fragility**: Only works when list is mutated in-place (push/delete). Fails on `setq` with fresh list (false miss) or `setcar` (false hit with stale data).
- **Version counter**: `(= (car cache) version)` works regardless of how the source data changes. Bump version in mutation functions.
- **Empty-list caching**: With `eq`, `(cdr '(nil))` = nil, so empty results never cache. Version counter has no such issue since cached value is a proper list.

Applied in `gptel-auto-workflow--normalized-projects`: replaced `(eq (car cache) projects-list)` with `(= (car cache) version)`.