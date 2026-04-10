---
title: Emacs Daemon Management
status: active
category: knowledge
tags: [daemon, emacs, process-management, troubleshooting, macos, linux]
---

# Emacs Daemon Management

## Overview

Emacs daemon mode runs a persistent Emacs server in the background, allowing rapid client connections via `emacsclient` with near-instant startup times. This guide covers critical patterns, anti-patterns, and troubleshooting techniques for managing Emacs daemons across platforms.

## Core Concepts

### What is an Emacs Daemon?

An Emacs daemon is a headless Emacs server process that:
- Runs continuously in the background
- Loads your init files once at startup
- Serves multiple `emacsclient` connections
- Maintains buffer, frame, and session state between connections

### Why Use a Daemon?

| Benefit | Description |
|---------|-------------|
| **Fast startup** | `emacsclient` connects in ~100ms vs ~2-5s for cold start |
| **Session persistence** | Buffers and state survive client disconnections |
| **Resource efficiency** | Single process handles multiple editor instances |
| **Remote-friendly** | Can serve connections via `TRAMP` over SSH |

## Critical Anti-Patterns

### 1. Stale Compiled Files (.elc)

**Problem:** Byte-compiled `.elc` files persist across daemon restarts, causing old code to run.

**Symptom Sequence:**
1. Edit `.el` source file
2. Restart daemon
3. Changes not reflected
4. Old compiled code still executing

**Root Cause:** Emacs daemon loads `.elc` if it exists, bypassing `.el` changes.

**Recovery Command:**
```bash
# Remove all compiled files
rm -f lisp/modules/*.elc

# Kill all Emacs processes
killall -9 Emacs

# Remove temp/socket files
rm -rf /tmp/emacs*

# Start fresh daemon
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

**Prevention Options:**

| Option | Implementation | Trade-off |
|--------|---------------|-----------|
| **Never compile** | Add `;; -*- no-byte-compile: t; -*-` to file header | Loses bytecode optimization |
| **Prefer newer** | `(setq load-prefer-newer t)` in early-init.el | Slight load time penalty |
| **Clean on restart** | `find . -name "*.elc" -delete` before restart | Requires discipline/script |

**Verification Test:**
```bash
rm -f lisp/modules/*.elc
emacs --batch -l lisp/modules/module.el -f some-function
```

### 2. Server Name Conflicts

**Problem:** Multiple cron jobs or processes using the same daemon server name cause "already running" errors.

**Symptom Messages:**
- `"Unable to start daemon: Emacs server named X already running"`
- `"failed to start worker daemon: X"`

**Root Cause:** Shared `SERVER_NAME` across independent processes.

**Solution Pattern:**
```bash
# Use action-specific server names
SERVER_NAME="copilot-auto-workflow"
SERVER_NAME="copilot-researcher"

# Separate log files per daemon
${SERVER_NAME}.log
```

**Fix Reference:** Commit `939928cf`

## Single Daemon Rule

**CRITICAL:** Only ONE Emacs daemon should run at any time.

### Why This Matters

| Issue | Consequence |
|-------|-------------|
| **Port binding** | Only one daemon can bind to server socket |
| **Client confusion** | `emacsclient` connects to first available daemon |
| **Resource waste** | Multiple daemons duplicate memory usage |
| **State inconsistency** | Buffers and worktrees get confused |

### Safe Daemon Start Script

```bash
#!/bin/bash
# ensure-single-daemon.sh - Safe daemon startup

echo "=== CHECKING FOR EXISTING DAEMONS ==="

DAEMON_COUNT=$(pgrep -f "Emacs.*daemon" | wc -l)
echo "Found $DAEMON_COUNT Emacs daemon process(es)"

if [ "$DAEMON_COUNT" -gt 0 ]; then
    echo "Killing existing Emacs processes..."
    pgrep -f "Emacs.*daemon" | while read pid; do
        echo "  Killing PID: $pid"
        kill -9 $pid 2>/dev/null
    done
    sleep 3
    
    # Force kill any stragglers
    REMAINING=$(pgrep -f "Emacs.*daemon" | wc -l)
    if [ "$REMAINING" -gt 0 ]; then
        echo "Forcing kill..."
      
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-UPatSv.txt. Use Read tool if you need more]...