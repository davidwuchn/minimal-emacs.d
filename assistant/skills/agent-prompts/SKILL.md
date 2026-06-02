---
name: agent-prompts
description: |
  System prompts for AI subagents (executor, grader, analyzer, researcher, etc.).
  Each agent has a specialized role and prompt that defines its behavior.
  Prompts live in assistant/agents/ and are loaded by nucleus-prompts.el.
version: 1.0
evolve-script: evolve_agent_prompts.py
metadata:
  evolution-stats:
    total-experiments: 870

level: atom
---
# Agent Prompts

## Overview

Each AI subagent has a dedicated system prompt that defines:
- Its role and responsibilities
- How to format output
- What tools it can use
- Constraints and safety rules

## Directory Structure

```
assistant/agents/
├── code_agent.md        # Primary agent (plan + execute)
├── plan_agent.md        # Planning mode (read-only)
├── executor.md          # Code execution agent
├── researcher.md        # Research and synthesis agent
├── explorer_agent.md    # Code exploration agent
├── reviewer.md          # Code review agent
├── introspector.md      # Self-introspection agent
├── analyzer.md          # Result analysis agent
├── comparator.md        # Experiment comparison agent
└── grader.md            # Output grading agent
```

## Agent Roles

### code_agent
**Role**: Primary agent for code improvement
**Mode**: Full tool access
**Tasks**: Plan, analyze, edit, validate

### plan_agent
**Role**: Read-only planning agent
**Mode**: Read-only tools only
**Tasks**: Analyze, plan, recommend (no edits)

### executor
**Role**: Execute code changes
**Mode**: Full tool access with validation
**Tasks**: Edit files, run tests, verify changes

### researcher
**Role**: Research and synthesize information
**Mode**: Web search, read files
**Tasks**: Find patterns, research topics, synthesize findings

### explorer_agent
**Role**: Explore codebase structure
**Mode**: Read-only navigation tools
**Tasks**: Map code, find symbols, understand architecture

### reviewer
**Role**: Review code changes
**Mode**: Read-only diff analysis
**Tasks**: Check quality, find issues, approve/reject

### introspector
**Role**: Self-analysis and improvement
**Mode**: Read system state
**Tasks**: Analyze performance, suggest improvements

### analyzer
**Role**: Analyze experiment results
**Mode**: Read data, compute statistics
**Tasks**: Find patterns, correlate variables, recommend next steps

### comparator
**Role**: Compare experiment outcomes
**Mode**: Read experiment data
**Tasks**: A/B test analysis, significance testing

### grader
**Role**: Grade agent outputs
**Mode**: Read output, apply rubric
**Tasks**: Score quality, detect issues, provide feedback

## Loading

Loaded by `nucleus-prompts.el`:

```elisp
(defun nucleus--register-gptel-directives ()
  "Register nucleus agent prompts as gptel directives."
  (let* ((dir nucleus-agents-dir)
         (agent-file (expand-file-name "code_agent.md" dir))
         (plan-file (expand-file-name "plan_agent.md" dir))
         (agent-sys (nucleus--read-gptel-agent-system agent-file))
         (plan-sys (nucleus--read-gptel-agent-system plan-file)))
    (when agent-sys
      (setf (alist-get 'nucleus-gptel-agent gptel-directives nil nil #'eq)
            agent-sys))
    (when plan-sys
      (setf (alist-get 'nucleus-gptel-plan gptel-directives nil nil #'eq)
            plan-sys))))
```

## Agent Presets

Agents are activated via gptel presets:

```elisp
(setq gptel-directives
      '((nucleus-gptel-agent . "...code_agent.md contents...")
        (nucleus-gptel-plan . "...plan_agent.md contents...")))
```

## Evolution

Agent prompts can be evolved based on:
- Success rates per agent type
- Error patterns (which agents fail)
- Tool usage patterns (which tools each agent uses best)

## Cross-Agent Integration

Agents reference each other:
- executor uses grader for validation
- researcher feeds analyzer
- explorer feeds executor with context
- reviewer gates staging

## Adding New Agents

1. Create `assistant/agents/NEW_AGENT.md`
2. Add loading logic to `nucleus-prompts.el`
3. Register in `gptel-directives`
4. Add to agent preset configuration
