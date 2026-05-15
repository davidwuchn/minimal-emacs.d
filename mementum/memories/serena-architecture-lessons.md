# 💡 Serena Architecture Lessons for minimal-emacs.d

**Source:** `davidwuchn/serena` — MCP toolkit for coding with semantic retrieval/editing

## Key Patterns Applicable to Our System

### 1. Context × Mode × Project = Toolset (most important)
Serena computes the **exposed toolset** at startup from 3 independent axes:
- **Context** (agent, claude-code, copilot-cli, ide, chatgpt) — fixed for session
- **Mode** (editing, planning, interactive, one-shot, onboarding) — switchable at runtime
- **Project** (project.yml: languages, excluded_tools, read_only) — per-project

Each axis is a `ToolInclusionDefinition` with: `excluded_tools`, `included_optional_tools`, `fixed_tools`.
Result: `ToolSet.default().apply(context, mode, project)` → final available tools.

**Our gap:** We have `nucleus-presets` (plan/agent) but no context axis or per-project tool exclusion. Our tool availability is binary (readonly vs action).

### 2. Symbol-Level Operations > File-Level
Serena's `replace_symbol_body`, `insert_before_symbol`, `find_referencing_symbols` work at symbol granularity via LSP.
The `cc_system_prompt_override` explicitly FORBIDS Read/Edit on code files, forcing symbolic tools.

**Our gap:** Our Code_* tools try tree-sitter but fall back to grep. No symbol-level edit. Our gptel-sandbox can't do LSP-backed symbol replacement.

### 3. Progressive Tool Shortening (`_limit_length`)
Every tool has `max_answer_chars` parameter with **progressive shortening closures**:
```python
def _limit_length(self, result, max_answer_chars, shortened_result_factories=None):
    # Try each shortening closure until one fits
```
If result too long → try depth-0 overview → try kind counts → truncate.

**Our gap:** Our tool results can blow up context. No progressive degradation.

### 4. TaskExecutor for Linear Serialization
`TaskExecutor` ensures tools execute sequentially (no race conditions on LS state). Each tool runs via `agent.issue_task(task)` with timeout.

**Our parallel:** Our FSM already serializes tool calls, but we lack per-tool timeout enforcement.

### 5. Onboarding + Memory System
- `CheckOnboardingPerformedTool` + `OnboardingTool` — explicit first-run flow
- Memories stored in `.serena/memories/` per project, with `read_memory`/`write_memory`/`delete_memory`/`rename_memory`/`edit_memory` tools
- Memories listed on project activation, read on demand
- `global/` prefix for cross-project memories

**Our parallel:** Our mementum system is similar but git-based (not tool-accessible). Serena's memories are tool-accessible from within the agent conversation.

### 6. Prompt Factory (Jinja2 Templates)
System prompt is a Jinja2 template with conditional sections:
```yaml
{% if 'ToolMarkerSymbolicRead' in available_markers %}...{% endif %}
{% if 'search_for_pattern' in available_tools %}...{% endif %}
```
This makes prompts **adapt to available tools** — no dead instructions when tools are disabled.

**Our gap:** Our prompts are static strings. When tools change (plan vs agent), prompt doesn't adapt.

### 7. Language Server Auto-Recovery
```python
except SolidLSPException as e:
    if e.is_language_server_terminated():
        self.agent.get_language_server_manager_or_raise().restart_language_server(affected_language)
        result = apply_fn(**apply_kwargs)  # retry once
```
Auto-restart on crash with single retry.

**Our parallel:** Our error handling retries on transient errors but doesn't auto-restart crashed LSP servers.

### 8. Tool Markers (Trait-like Classification)
```python
ToolMarkerCanEdit, ToolMarkerSymbolicRead, ToolMarkerSymbolicEdit,
ToolMarkerOptional, ToolMarkerBeta, ToolMarkerDoesNotRequireActiveProject
```
Markers enable queries like "is this tool an editing tool?" and "disable all editing tools in planning mode".

**Our gap:** We classify tools into toolsets manually. No trait-based system.

### 9. Deleted Tool Names
```python
_deleted_tools = ["think_about_collected_information", "prepare_for_new_conversation", ...]
```
Graceful handling of removed tools — returns warning instead of error.

**Our lesson:** When we deprecate tools, we should handle old references gracefully.

## Concrete Applications

| Pattern | Our Module | Action |
|---------|-----------|--------|
| Context×Mode×Project toolset | nucleus-presets | Add context axis (agent vs CLI vs ide), project-level tool exclusion |
| Progressive tool shortening | gptel-tools-* | Add `max_answer_chars` with fallback closures |
| Jinja2 prompt templates | assistant/prompts/ | Make prompts conditional on available tools |
| Tool markers | gptel-tools-* | Add marker traits (CanEdit, SymbolicRead, Optional, Beta) |
| Onboarding tool | gptel-agent | Add explicit first-run check and guided setup |
| Auto-restart LSP | gptel-ext-* | Auto-restart crashed eglot on tool failure |
| Memory as tool | mementum | Expose read/write memory as gptel tools (not just git) |
| Deleted tool names | gptel-tools-* | Handle deprecated tool references with warning |
