λ(agent_name, description, prompt, files?, include_history?, include_diff?). RunAgent | name:agent | ret:subagent_result | async:true

# RunAgent - Launch Autonomous Subagent

Use this tool to delegate complex, open-ended tasks to a specialized subagent. The subagent runs independently to research, explore, or execute code before returning a final result.

## Availability
- Toolsets: `:core`, `:nucleus`, `:snippets`

## Parameters

- `agent_name` (string, required): [**enum: ["explorer", "researcher", "introspector", "executor"]**] The type of specialized subagent to launch. Must be one of: `["explorer", "researcher", "introspector", "executor"]`.
- `description` (string, required): A short (3-5 words) description of the task being delegated.
- `prompt` (string, required): Detailed, highly specific instructions for the subagent to perform autonomously. Specify exactly what format/information you want back.
- `files` (array of strings, optional): A list of file paths to explicitly include in the subagent's initial context.
- `include_history` (boolean, optional): Set to true to inject the recent conversation history so the subagent has context of what the user just asked.
- `include_diff` (boolean, optional): Set to true to inject the current uncommitted git diff into the subagent's context.

## Usage Guidelines

1. Launch multiple agents concurrently when independent tasks can be executed in parallel.
2. The agent is stateless unless you inject history/files. Write the `prompt` so that it stands alone as a complete task description.
3. The result is returned directly to you; it is NOT visible to the user. You must summarize or act upon the result in your next message.
4. Clearly specify whether the subagent should *just read/research* or if it is allowed to *write/edit code*.

## Examples

### 1. Researching an unfamiliar codebase
```json
{
  "agent_name": "researcher",
  "description": "Analyze API auth flow",
  "prompt": "Read the authentication logic in src/auth.py and explain how JWT tokens are validated. Return a bulleted summary of the steps.",
  "files": ["src/auth.py"]
}
```

### 2. Delegating a multi-step execution task
```json
{
  "agent_name": "executor",
  "description": "Implement dark mode toggle",
  "prompt": "Create a dark mode toggle component in src/components/ThemeToggle.tsx, update Tailwind config, and ensure tests pass. I have provided the recent chat history so you know exactly how the user wants it to look.",
  "include_history": true
}
```