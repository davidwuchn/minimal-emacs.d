---
title: Prefer Git Submodules Over ELPA for Core Packages
date: 2026-05-17
symbol: ❌
---

# Prefer Git Submodules Over ELPA for Core Packages

ELPA packages under `var/elpa/` are version-locked snapshots. Git submodules
under `packages/` are tracked branches with latest fixes.

## Why submodules are always better

| Aspect | ELPA (`var/elpa/gptel-20250427`) | Submodule (`packages/gptel`) |
|--------|----------------------------------|-----------------------------|
| Version | Frozen at 2025-04-27 snapshot | Latest commit from upstream |
| Updates | Requires new ELPA download | `git pull` in submodule |
| Recursion guards | ❌ Missing (gptel-abort depth guard) | ✅ Present (896dcfb, 2a98416) |
| v0.9.9.5 fixes | ❌ Missing (utf-8 tool args, INFO passing) | ✅ Present (d7c103c, f915a8b) |
| Autoloads | Pre-built, may be stale | Regenerated with `package-generate-autoloads` |
| Git tracking | Not tracked | Tracked in main repo's `.gitmodules` |

## Rule

```
λ load_path(x). submodule(x) > elpa(x) | tracked > frozen
```

Always use `-L packages/gptel -L packages/gptel-agent` in batch commands and
test runners, never `-L var/elpa/gptel-*`. The ELPA version is missing critical
fixes (recursion guards, tool inspection, utf-8 encoding).

Our `run-tests.sh` already does this correctly at lines 89-90.
