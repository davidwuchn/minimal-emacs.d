## VSM Stage Boundary Enforcement — Key Insight

**Pattern**: Each pipeline stage has explicit `will_not_do` constraints preventing scope creep.

**Stage contract**:
| Stage | Produces ONLY | Will NOT do |
|-------|---------------|-------------|
| research | facts | opinions, action |
| assess | insights | opinions, code |
| spec | plans | implementation |
| code | implementation | unrequested features |

**Application for auto-workflow**:
1. Add `:will-not-do` properties to each stage function in `gptel-auto-workflow-*.el`
2. Validate stage outputs before passing to next stage
3. Prevent the 13 bug-fixes pattern by catching scope-creep bugs early

**Example**:
```elisp
(defun gptel-workflow-synthesize (context)
  "Synthesize facts from research.
Will NOT: generate opinions, suggest implementations, propose features.")
```

**Priority**: High — directly addresses the bug-fix focus of recent commits.
