---
name: tool-prompts
description: |
  Prompt templates for AI tools (Read, Write, Bash, Edit, etc.).
  Each tool has a specific prompt that guides the AI on how to use it correctly.
  Prompts live in assistant/prompts/tools/ and are loaded by nucleus-prompts.el.
version: 1.0
evolve-script: evolve_tool_prompts.py
metadata:
  evolution-stats:
    total-experiments: 870

level: atom
---
# Tool Prompts

## Overview

Each AI tool has a dedicated prompt template that explains:
- What the tool does
- When to use it
- How to format arguments
- Common pitfalls to avoid

## Directory Structure

```
assistant/prompts/tools/
├── bash.md              # Bash command execution
├── read_file.md         # File reading
├── write_file.md        # File writing
├── edit_file.md         # File editing (patch-based)
├── apply_patch.md       # Apply patch operations
├── grep.md              # Content search
├── glob.md              # File pattern matching
├── web_search.md        # Web search
├── web_fetch.md         # Fetch URL content
├── run_agent.md         # Run subagent
├── programmatic.md      # Programmatic tool execution
├── eval.md              # Emacs Lisp evaluation
├── code_map.md          # Code structure mapping
├── code_inspect.md      # Code inspection
├── code_replace.md      # Code replacement
├── code_usages.md       # Find code usages
├── diagnostics.md       # Diagnostic information
├── describe_symbol.md   # Symbol documentation
├── get_symbol_source.md # Symbol source code
├── find_buffers_and_recent.md # Buffer and recent files
├── preview.md           # Preview changes
├── todo_write.md        # Todo list management
├── list_skills.md       # List available skills
├── skill.md             # Load skill content
├── create_skill.md      # Create new skill
├── compact_chat.md      # Chat compaction
├── youtube.md           # YouTube operations
├── move.md              # File movement
├── mkdir.md             # Directory creation
├── insert.md            # Content insertion
└── USAGE_STATS.md       # Tool usage statistics
```

## Loading

Loaded by `nucleus-prompts.el`:

```elisp
(defun nucleus-load-tool-prompts ()
  "Load all tool prompt files into `nucleus-tool-prompts'."
  (let ((base (nucleus--resolve-tool-prompts-dir)))
    (setq nucleus-tool-prompts
          (seq-filter
           #'identity
           (mapcar
            (lambda (entry)
              (let* ((key (car entry))
                     (file (cdr entry))
                     (path (and base (expand-file-name file base)))
                     (text (and path (nucleus--read-file-if-exists path))))
                (when text
                  (cons key text))))
            nucleus-tool-prompt-files)))))
```

## Tool Prompt Registry

| Tool | File | Purpose |
|------|------|---------|
| Bash | bash.md | Execute bash commands safely |
| Read | read_file.md | Read file contents |
| Write | write_file.md | Write files atomically |
| Edit | edit_file.md | Edit files with patches |
| ApplyPatch | apply_patch.md | Apply patches |
| Grep | grep.md | Search file contents |
| Glob | glob.md | Match file patterns |
| WebSearch | web_search.md | Search the web |
| WebFetch | web_fetch.md | Fetch URL content |
| RunAgent | run_agent.md | Delegate to subagent |
| Programmatic | programmatic.md | Execute programmatically |
| Eval | eval.md | Evaluate Emacs Lisp |
| Code_Map | code_map.md | Map code structure |
| Code_Inspect | code_inspect.md | Inspect code details |
| Code_Replace | code_replace.md | Replace code |
| Code_Usages | code_usages.md | Find usages |
| Diagnostics | diagnostics.md | Get diagnostics |
| describe_symbol | describe_symbol.md | Document symbols |
| get_symbol_source | get_symbol_source.md | Get source |
| find_buffers_and_recent | find_buffers_and_recent.md | Find buffers |
| Preview | preview.md | Preview changes |
| TodoWrite | todo_write.md | Manage todos |
| list_skills | list_skills.md | List skills |
| Skill | skill.md | Load skill |
| create_skill | create_skill.md | Create skill |
| compact_chat | compact_chat.md | Compact chat |
| YouTube | youtube.md | YouTube ops |
| Move | move.md | Move files |
| Mkdir | mkdir.md | Make directories |
| Insert | insert.md | Insert content |

## Usage in Agent Prompts

Tool prompts are injected into agent system prompts:

```elisp
(defun nucleus-gptel-tool-prompts ()
  "Return the nucleus tool-prompt alist."
  (nucleus-ensure-loaded)
  nucleus-tool-prompts)
```

## Evolution

Tool prompts can be evolved based on:
- Tool usage frequency (from USAGE_STATS.md)
- Error patterns (which tools fail most)
- Success correlations (which tool combinations work best)

## Adding New Tools

1. Create `assistant/prompts/tools/NEW_TOOL.md`
2. Add entry to `nucleus-tool-prompt-files` in `nucleus-prompts.el`
3. Run `nucleus-refresh-prompts` to load
