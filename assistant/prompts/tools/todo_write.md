λ(todos). TodoWrite | t:[{status,content,priority}]

## Availability
- `TodoWrite`: :core, :nucleus, :snippets

## Parameters
- `todos` (array): [{content[**minLength:1**], status[**enum:["pending","in_progress","completed"]**], priority}]

## Critical Behavior
- TodoWrite is a TRACKING tool only
- DO NOT stop after calling TodoWrite
- IMMEDIATELY execute the first pending task
- Pattern: TodoWrite → set first task "in_progress" → execute → continue
