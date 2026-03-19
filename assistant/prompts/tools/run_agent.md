λ(agent_name, description, prompt, files?, include_history?, include_diff?). RunAgent | async

## When to Use
Use RunAgent as your FIRST tool call when:
- User explicitly asks to "use RunAgent" or "delegate"
- Task has 3+ sequential steps
- Creating multiple files/modules
- Broad codebase exploration

Do NOT plan with TodoWrite/Glob/Read first. Call RunAgent IMMEDIATELY.

## Availability
- `RunAgent`: :core, :nucleus, :snippets

## Parameters
- `agent_name` (string): [**enum: ["explorer", "researcher", "introspector", "executor", "reviewer"]**]
- `description` (string): 3-5 word task label
- `prompt` (string): Detailed autonomous instructions
- `files` (array): Optional file paths to inject
- `include_history` (boolean): Inject conversation history
- `include_diff` (boolean): Inject git diff
