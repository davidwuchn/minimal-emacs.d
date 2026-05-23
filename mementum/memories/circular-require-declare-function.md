# ✅ Circular Require: Use declare-function Not require

tags: circular-dependency, require, declare-function, evolution

## Symptom
`(require 'gptel-tools-agent-base)` in evolution.el created circular dependency:
evolution.el → tools-agent-base → production → evolution.el → Recursive load error.

## Root Cause
The daemon added bare `require` to fix a `declare-function` that pointed to the wrong module. The require created a cycle.

## Fix
Used `declare-function` with the CORRECT module name (`gptel-tools-agent-base` instead of `gptel-tools-agent`). `declare-function` tells the byte compiler where the function lives without creating a require cycle. All callers use `fboundp` guards.

## Files Changed
- lisp/modules/gptel-auto-workflow-evolution.el: require → declare-function with correct module
