# accidental-deletion-bdd-commit

💡 **Large single-file commits need diff review.** The Allium BDD commit added 60 lines of BDD infrastructure but also deleted 512 lines of pipeline stages, backend comparison, model comparison, and quality gates from evolution.el. The functions were still actively called at lines 1848, 1896-1897. The commit message only mentioned "Allium BDD" with no hint of deletions.

**Lesson:** When adding new features to a large file, verify the diff — not just the stat line — before pushing. 512 lines of deletions in a 60-line addition commit is a red flag. Callers in the same file should have been caught by the byte-compiler if warnings were checked.

**Detection:** `git diff upstream/main..origin/main --stat` showed +137/-512. `grep` for deleted function names revealed active callers. Restored from `git show upstream/main:file.el`.
