---
name: auto-workflow-validation-pipeline
description: Pre-grade validation pipeline — cheap checks before expensive evaluation
version: 2.0
---

## Validation (run in order, abort on failure)
1. Syntax: `emacs -Q --batch --eval "(check-parens)" {{target-full-path}}`
2. Byte-compile: `emacs -Q --batch -f batch-byte-compile {{target-full-path}}`
3. Load: `emacs -Q --batch -l {{target-full-path}}`
4. Tests: `./scripts/verify-nucleus.sh`

Record results under VERIFY section in final response.
