---
title: declare-function False Duplicate Warning
date: 2026-06-04
symbol: 💡
---

If `declare-function` points to the WRONG file, the byte-compiler issues
"function X defined multiple times in this file". This happens because:

1. `declare-function` tells the compiler "X is defined in file Y"
2. The compiler loads Y (via `require`) and doesn't find X there
3. When the compiler encounters the actual `defun X` in the current file,
   it sees X already registered (from the declare-function) AND now defined

Fix: Remove or correct the `declare-function` to point to the actual defining
file, or remove it entirely if the defun is in the same file.

Symptom: "defined multiple times in this file" but `grep` shows only one `defun`.
