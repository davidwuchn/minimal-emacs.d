λ(todos). TodoWrite | t:[{status,content,priority}] | ret:updated_list

# TodoWrite - Manage Task List

## Purpose
Create, update, and track tasks in a structured todo list. Used for planning and tracking progress on multi-step tasks.

## Availability
- `TodoWrite`: :core, :nucleus, :snippets

## When to Use
- Breaking down complex tasks into steps
- Tracking progress on multi-file changes
- Planning implementation phases
- Keeping track of pending work

## Usage
```
TodoWrite{todos: [{content: "Step 1", status: "in_progress", priority: "high"}, ...]}
```

## Parameters
- `todos` (required): Array of todo objects with:
  - `content` (string): [**minLength: 1**] Task description
  - `status` (string): [**enum: ["pending", "in_progress", "completed"]**] "pending", "in_progress", "completed", "cancelled"
  - `priority` (string): "high", "medium", "low"

## Returns
Updated todo list confirmation.

## Examples
```
# Create initial todo list
TodoWrite{
  todos: [
    {content: "Read existing code", status: "completed", priority: "high"},
    {content: "Implement feature", status: "in_progress", priority: "high"},
    {content: "Write tests", status: "pending", priority: "medium"},
    {content: "Update docs", status: "pending", priority: "low"}
  ]
}
→ Todo list updated with 4 tasks

# Update task status
TodoWrite{
  todos: [
    {content: "Read existing code", status: "completed", priority: "high"},
    {content: "Implement feature", status: "completed", priority: "high"},
    {content: "Write tests", status: "in_progress", priority: "medium"},
    {content: "Update docs", status: "pending", priority: "low"}
  ]
}
→ Todo list updated: "Implement feature" marked as completed
```

## Task Status Values
| Status | Meaning | When to Use |
|--------|---------|-------------|
| `pending` | Not started yet | Future work |
| `in_progress` | Currently working on | Active task |
| `completed` | Finished successfully | Done work |
| `cancelled` | Abandoned/skipped | Won't do |

## Priority Levels
| Priority | Meaning | Examples |
|----------|---------|----------|
| `high` | Critical, do first | Core functionality, bug fixes |
| `medium` | Important | Features, improvements |
| `low` | Nice to have | Documentation, cleanup |

## Best Practices
1. **Keep tasks atomic**: Each task should be a single, completable unit
2. **Update frequently**: Mark tasks complete as you finish them
3. **Be specific**: Clear task descriptions help track progress
4. **Limit in_progress**: Focus on 1-2 tasks at a time

## Notes
- Visible in agent context for planning
- Helps break down complex requests
- Use at start of multi-step tasks
- Update after completing each step

## Related Tools
- `Agent` - Delegate complex tasks
- `RunAgent` - Run specialized subagents
