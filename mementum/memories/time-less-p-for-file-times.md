# File Modification Times Need `time-less-p`

**Date**: 2026-06-15
**Category**: anti-pattern
**Related**: gptel-mementum-check-synthesis-candidates, file-attribute-modification-time, time-less-p

## Insight

`file-attribute-modification-time` returns native time values, not numbers. Comparing them with `max` can throw `wrong-type-argument number-or-marker-p` and break synthesis discovery.

## Fix

Use `time-less-p` to compute the newest time value, or convert to `float-time` before numeric comparison.

## Test pattern

Create 3 temp memory files under one topic and assert `gptel-mementum-check-synthesis-candidates` returns candidates without error.
