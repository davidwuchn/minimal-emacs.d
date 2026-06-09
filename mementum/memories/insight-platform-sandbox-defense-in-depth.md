---
valid-from: 2026-06-09T14:30
---

# Insight: platform sandbox is defense-in-depth layer, not anti-pattern

**Previous classification**: Research from Magent classified seatbelt/bubblewrap
as "anti-pattern — out of scope for Emacs-native flow."

**Correction**: This was wrong. The Emacs-native sandbox (expression whitelisting)
protects Lisp code execution, but cannot contain shell processes when Bash tool
is active. Platform sandbox is the **missing layer** in defense-in-depth:

```
sanitize → acl → expression → platform (seatbelt|bubblewrap)
```

**Strategy**: macOS → `sandbox-exec` (seatbelt), Linux → `bubblewrap` (bwrap).
Both deny-by-default with workspace-scoped allowlists.

**Direct experience**: bubblewrap on Linux works well for containing Bash tool
execution without breaking legitimate workflows.

**AGENTS.md updated**: sandbox lambda now includes `macOS(x) → seatbelt(x) |
linux(x) → bubblewrap(x) | defense_depth(x): sanitize → acl → expression → platform`

**Knowledge page**: mementum/knowledge/platform-sandbox-strategy.md
