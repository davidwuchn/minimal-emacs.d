λ(agent_name, description, prompt, files?, include_history?, include_diff?). RunAgent | name:agent | ret:subagent_result | async:true
λ(subagent_type, description, prompt, files?, include_history?, include_diff?). Agent | req:subagent | ret:result

# Agent / RunAgent - Launch Autonomous Subagent

Use these tools to delegate complex, open-ended tasks to a specialized subagent. The subagent runs independently to research, explore, or execute code before returning a final result.

## Parameters

- `subagent_type` / `agent_name` (string, required): The type of specialized subagent to launch (e.g., "explorer", "researcher", "executor", "introspector").
- `description` (string, required): A short (3-5 words) description of the task being delegated.
- `prompt` (string, required): Detailed, highly specific instructions for the subagent to perform autonomously. Specify exactly what format/information you want back.
- `files` (array, optional): A list of file paths to explicitly include in the subagent's initial context.
- `include_history` (boolean, optional): Set to true to inject the recent conversation history so the subagent has context of what the user just asked.
- `include_diff` (boolean, optional): Set to true to inject the current uncommitted git diff into the subagent's context.

## Usage Guidelines

1. Launch multiple agents concurrently when independent tasks can be executed in parallel.
2. The agent is stateless unless you inject history/files. Write the `prompt` so that it stands alone as a complete task description.
3. The result is returned directly to you; it is NOT visible to the user. You must summarize or act upon the result in your next message.
4. Clearly specify whether the subagent should *just read/research* or if it is allowed to *write/edit code*.