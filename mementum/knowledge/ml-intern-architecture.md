---
title: ml-intern Architecture Patterns
status: active
category: research
tags: [agent, huggingface, tool-system, session-management]
related: [context-mode, doom-loop, auto-workflow]
depends-on: [research-insights-think-in-code]
---

# ml-intern Architecture Patterns

**Source:** `davidwuchn/ml-intern` — Fork of HuggingFace's open-source ML engineer agent

## Architecture Overview

```
┌─────────────────────────────────────────┐
│            User/CLI                     │
└────────────┬────────────────────────────┘
             │ Operations (queue)  Events ↑
             ↓                            │
┌────────────────────────────────────────┐
│       submission_loop (agent_loop.py)  │
│                                        │
│  ┌──────────────────────────────────┐  │
│  │ Session                          │  │
│  │  ├─ ContextManager (messages)    │  │
│  │  ├─ ToolRouter                   │  │
│  │  ├─ DoomLoopDetector             │  │
│  │  └─ ApprovalPolicy               │  │
│  └──────────────────────────────────┘  │
│                                        │
│  Loop:                                 │
│    1. LLM call (litellm.acompletion)   │
│    2. Parse tool_calls[]               │
│    3. Doom loop check                  │
│    4. Approval check (if needed)       │
│    5. ToolRouter.execute()             │
│    6. Add result to context            │
│    7. Repeat if tool_calls exist       │
└────────────────────────────────────────┘
```

## Key Patterns

### 1. Tool System (`tools.py`)

- **ToolSpec**: `name`, `description`, `parameters` (OpenAI schema), `handler` (async callable)
- **ToolRouter**: Registry for built-in + MCP tools
- **MCP integration**: FastMCP client for external tool servers
- **Order matters**: Tools ordered by importance in `create_builtin_tools()`

### 2. Doom Loop Detection (`doom_loop.py`)

- **Tool Call Signatures**: `(name, args_hash, result_hash)` — includes result so polling isn't flagged
- **Identical consecutive**: 3+ same calls → corrective prompt injected
- **Repeating sequence**: `[A,B,A,B]` pattern → sequence flagged
- **Injection point**: Before each LLM call in the loop

### 3. Approval Policy (`agent_loop.py`)

- **Budget-based auto-approval**: Session `auto_approval_cost_cap_usd` + `auto_approval_estimated_spend_usd`
- **YOLO mode**: Config-level bypass (CLI only)
- **Scheduled jobs**: Always require approval (recurring/unbounded)
- **CPU jobs**: Configurable `confirm_cpu_jobs`

### 4. Context Management

- **Auto-compaction**: When context exceeds threshold
- **CompactionFailedError handling**: Terminates session cleanly, not endless retry loop
- **Session upload to HF**: Claude Code JSONL format for Agent Trace Viewer

### 5. Event System

- `processing`, `ready`, `assistant_chunk`, `assistant_message`
- `tool_call`, `tool_output`, `tool_log`, `tool_state_change`
- `approval_required`, `turn_complete`, `error`, `interrupted`
- `compacted`, `undo_complete`, `shutdown`

### 6. LLM Retry Logic

- **Transient errors**: Timeout, 503, 502, 500 → exponential backoff
- **Rate limits**: 429 → longer delays (30s, 60s)
- **Effort config errors**: Auto-heal by stripping unsupported thinking params
- **Context overflow**: Compact → retry; if compaction fails → terminate

## Application to minimal-emacs.d

| Pattern | Current Status | Potential Application |
|---------|---------------|----------------------|
| Doom loop detection | None | Add to AutoTTS controller, researcher loop |
| Tool ordering by priority | Implicit (gptel-tools-programmatic first) | Explicit ordering in tool registry |
| Budget-based approval | Hardcoded thresholds | Session-level cost caps for HF Jobs |
| Event system | ECA callback-based | Unified event queue for frontend/backend |
| Compaction on overflow | Manual | Auto-compaction when context exceeds threshold |
| Session upload | None | Upload traces to HF dataset for replay |

## References

- Source repo: https://github.com/davidwuchn/ml-intern
- Doom loop detector: `agent/core/doom_loop.py`
- Agent loop: `agent/core/agent_loop.py`
- Tool system: `agent/core/tools.py`
- Context manager: `agent/context_manager/manager.py`