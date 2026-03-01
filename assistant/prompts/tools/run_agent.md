λ(agent_name, description, prompt, files?, include_history?, include_diff?). run_agent | name:agent | ret:subagent_result | async:true

# RunAgent - Run Subagent by Name

## Purpose
Delegate a task to a specialized subagent by name. Runs asynchronously with configurable context injection.

## When to Use
- Need specialized expertise (explorer, researcher, introspector)
- Complex multi-step tasks requiring focused attention
- Parallel task execution
- Offloading specific subtasks while continuing main work

## Usage
```
RunAgent{
  agent_name: "explorer",
  description: "Find all API endpoints",
  prompt: "Search the codebase for all HTTP API endpoint definitions...",
  files?: ["src/api.py"],
  include_history?: false,
  include_diff?: false
}
```

## Parameters
- `agent_name` (required): Agent name from available agents
- `description` (required): Short task label (1-2 sentences)
- `prompt` (required): Full task prompt with detailed instructions
- `files` (optional): List of file paths to inject into subagent context
- `include_history` (optional): If true, injects recent conversation history
- `include_diff` (optional): If true, injects git diff HEAD into context

## Available Agents
| Agent | Purpose | Best For |
|-------|---------|----------|
| `explorer` | Deep codebase exploration | Finding patterns, architecture analysis |
| `researcher` | Web/codebase research | External docs, StackOverflow, GitHub |
| `introspector` | Emacs introspection | Elisp debugging, buffer inspection |
| `executor` | Task execution | Running commands, applying changes |

## Returns
Subagent result with findings, analysis, or completed work.

## Examples
```
# Use explorer to find API endpoints
RunAgent{
  agent_name: "explorer",
  description: "Find all API endpoints",
  prompt: "Search the codebase for all HTTP API endpoint definitions. Look for @app.route, @api.get, def routes, etc. Report file:line for each endpoint found.",
  files: ["src/api.py", "src/routes.py"]
}
→ Found 15 API endpoints:
  - GET /users (src/api.py:45)
  - POST /users (src/api.py:52)
  ...

# Use researcher for external docs
RunAgent{
  agent_name: "researcher",
  description: "Research best practices for async Python",
  prompt: "Find current best practices for async/await in Python 3.11+. Search official docs, Real Python, and recent blog posts. Summarize key recommendations."
}
→ Based on Python 3.11 docs and recent articles:
  1. Use asyncio.run() for entry points
  2. Prefer asyncio.create_task() over ensure_future()
  ...

# Use introspector for Elisp debugging
RunAgent{
  agent_name: "introspector",
  description: "Debug Elisp function",
  prompt: "Inspect the function 'my-custom-function' in current buffer. Show byte-compilation warnings, macro expansions, and any advice attached.",
  include_history: true
}
→ Function 'my-custom-function':
  - Defined in: ~/.emacs.d/lisp/my-config.el:145
  - Byte-compile warnings: None
  - Advice: :around 'advice-around-func
  ...
```

## ⚠️ Important Notes
- **Async execution**: Subagent runs independently, main agent can continue working
- **Context injection**: Use `files`, `include_history`, `include_diff` to provide necessary context
- **Timeout**: Subagents have configurable timeout (default: 300s)
- **Stateless**: Each subagent invocation is independent (no shared state)

## Error Handling
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Unknown agent: X" | Invalid agent name | Use one of: explorer, researcher, introspector, executor |
| "Timeout after X seconds" | Task took too long | Increase timeout or break into smaller tasks |
| "No files found" | Invalid file paths | Check file paths exist and are accessible |

## Best Practices
1. **Be specific**: Clear, detailed prompts get better results
2. **Provide context**: Use `files` parameter to inject relevant files
3. **Set expectations**: Include output format in prompt
4. **Parallel execution**: Run multiple subagents for independent tasks
5. **Review results**: Subagent output should be reviewed before acting on it

## Notes
- Subagents use exponential backoff for stability
- Results are injected into main conversation context
- Use for complex tasks that benefit from focused attention
- Not suitable for simple lookups (use Code_* tools instead)
