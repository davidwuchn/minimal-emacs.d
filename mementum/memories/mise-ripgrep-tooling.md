# mise ripgrep tooling

**Date**: 2026-05-01
**Category**: tooling
**Related**: search, rg, mise, opencode

## Insight

This workspace removed the broken `/home/davidwu/.cargo/bin/rg` binary because it was incompatible with Pi5/Debian 16KB pages. The OpenCode `Grep` and `Glob` tools may still try that exact path and fail with `ChildProcess.spawn (/home/davidwu/.cargo/bin/rg ...)`.

Use Bash with mise-managed ripgrep for searches:

```bash
mise exec cargo:ripgrep -- rg ...
```

Do not reinstall or depend on `.cargo/bin/rg` here. If file/content search fails unexpectedly, first check whether the tool tried the removed cargo path. This avoids confusing search failures with missing code.
