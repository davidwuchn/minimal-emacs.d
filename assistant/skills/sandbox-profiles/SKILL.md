---
name: sandbox-profiles
description: |
  Defines tool permission profiles for programmatic agent execution.
  Controls which tools an agent can use based on execution mode and project type.
version: 1.0
evolve-script: evolve_profiles.py
metadata:
  category: security
  author: auto-workflow
  evolution-stats:
    total-experiments: 870

---
# Sandbox Tool Profiles

## Overview

Different execution contexts require different tool permissions:
- **Plan mode**: Read-only tools only
- **Agent mode**: Full tool access with confirmation for destructive operations
- **Project-specific**: Custom tool sets per language/framework

## Profiles

### emacs-lisp (Default)
```json
{
  "allowed": ["Read", "Grep", "Glob", "Edit", "ApplyPatch", "Code_Map", "Code_Inspect", "Code_Replace", "Code_Usages", "Diagnostics", "describe_symbol", "get_symbol_source", "find_buffers_and_recent"],
  "readonly": ["Read", "Grep", "Glob", "Code_Map", "Code_Inspect", "Code_Usages", "Diagnostics", "describe_symbol", "get_symbol_source", "find_buffers_and_recent"],
  "confirming": ["Edit", "ApplyPatch", "Code_Replace"],
  "timeout": 15,
  "max_calls": 25,
  "result_limit": 4000
}
```

### web-development
```json
{
  "allowed": ["Read", "Grep", "Glob", "Edit", "ApplyPatch", "Code_Map", "WebFetch", "WebSearch", "Bash", "Diagnostics"],
  "readonly": ["Read", "Grep", "Glob", "Code_Map", "WebFetch", "WebSearch", "Diagnostics"],
  "confirming": ["Edit", "ApplyPatch", "Bash"],
  "timeout": 30,
  "max_calls": 50,
  "result_limit": 8000
}
```

### data-science
```json
{
  "allowed": ["Read", "Grep", "Glob", "Edit", "Bash", "Diagnostics", "Programmatic"],
  "readonly": ["Read", "Grep", "Glob", "Diagnostics"],
  "confirming": ["Edit", "Bash", "Programmatic"],
  "timeout": 60,
  "max_calls": 100,
  "result_limit": 16000
}
```

### readonly-audit
```json
{
  "allowed": ["Read", "Grep", "Glob", "Code_Map", "Code_Inspect", "Code_Usages", "Diagnostics", "describe_symbol", "get_symbol_source"],
  "readonly": ["Read", "Grep", "Glob", "Code_Map", "Code_Inspect", "Code_Usages", "Diagnostics", "describe_symbol", "get_symbol_source"],
  "confirming": [],
  "timeout": 15,
  "max_calls": 25,
  "result_limit": 4000
}
```

## Rules

1. **Progressive Disclosure**: Start with readonly, escalate to confirming only when needed
2. **Confirmation Required**: Destructive tools (Edit, Bash, ApplyPatch) must be confirmed
3. **Timeout Protection**: Long-running tools have strict timeouts
4. **Call Limits**: Prevent infinite loops with max tool call limits

## Integration

Load profile in Emacs Lisp:
```elisp
(let ((skill (gptel-auto-workflow--load-skill "sandbox-profiles")))
  (plist-get skill :profiles))
```

## Scripts

- `scripts/validate_profile.py` - Validate profile JSON against schema
- `scripts/generate_profile.py` - Generate profile from project analysis

## Evolved Tool Profiles

Based on analysis of 0 experiments.

| Tool | Level | Success Rate | Experiments |
|------|-------|--------------|-------------|
