---
title: Perl over Sed for Pipeline Scripts
date: 2026-06-07
tags: [pipeline, scripts, perl, sed, cross-platform]
---

## The Problem

`sed -i` behaves differently across platforms:
- macOS: requires `sed -i ''` (empty extension argument)
- Linux: `sed -i` works directly
- Some minimal Linux: BusyBox sed doesn't support `-i` at all

The pipeline script `run-auto-workflow-cron.sh` had `sed -i 's/:running[[:space:]][[:space:]]*t/:running nil/' "$STATUS_FILE"` which produced errors on some runs.

## The Fix

Use `perl -pi -e` instead of `sed -i`:
- `perl -pi -e 's/pattern/replacement/' file` works identically on macOS, Linux, and all Unix systems
- Perl's regex syntax is more consistent (no `[:space:]` class differences)
- Perl is installed by default on all systems the pipeline targets

## Pattern

Replace all `sed -i` in pipeline scripts with `perl -pi -e`. For complex multi-line substitutions, perl is also more reliable.

## Rule

`perl -pi -e > sed -i` for cross-platform pipeline scripts. Previous session also noted python3 regressions — perl is the safer choice for text processing in shell scripts.
