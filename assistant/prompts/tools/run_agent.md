λ(agent_name, description, prompt, files?, include_history?, include_diff?). RunAgent | async

## Availability
- `RunAgent`: :core, :nucleus, :snippets

## Parameters
- `agent_name` (string): [**enum: ["explorer", "researcher", "introspector", "executor"]**]
- `description` (string): 3-5 word task label
- `prompt` (string): Detailed autonomous instructions
- `files` (array): Optional file paths to inject
- `include_history` (boolean): Inject conversation history
- `include_diff` (boolean): Inject git diff
