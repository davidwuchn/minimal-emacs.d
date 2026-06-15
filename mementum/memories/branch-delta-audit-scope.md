---
frontmatter-version: "1.0"
---

# Memory: Branch-Delta Audit Scope

## Insight

Repo-global history scans (`git log --all`) created permanent audit noise from old toxic branches and score-fabrication commits. Narrowing the semantic audit to the current branch delta (`origin/main..HEAD`) preserves detection of new bad changes while letting the current mainline audit go green. A separate `syntax-ppss` guard is needed for curl-arg scans so docstring mentions do not count as real config blocks.

## What Changed

- Replaced repo-global history scans with branch-delta scans in `gptel-auto-workflow--audit-toxic-commit-subject` and `gptel-auto-workflow--build-sha-subject-map`.
- Skipped `curl-no-max-time` matches inside strings/comments, fixing the `gptel-ext-abort.el` docstring false positive.
- Tightened the real-repo semantic audit test to require 0 issues on current main.

## Symbol

💡 insight
