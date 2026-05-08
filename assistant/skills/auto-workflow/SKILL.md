---
name: auto-workflow
description: |
  Self-evolving AI coding agent for Emacs Lisp projects. Automates experiment-based
  code improvement with staging, validation, and skill evolution. Use when you need
  to optimize Emacs Lisp modules, fix bugs, or improve code quality through systematic
  experimentation.
version: 2.0
updated: 2026-05-08
metadata:
  author: auto-workflow
  category: ai-agent
  language: emacs-lisp
  license: MIT
compatibility: |
  Requires Emacs 29+, Python 3.8+, git, and internet access for external research.
  Designed for Emacs Lisp projects using gptel-agent framework.
allowed-tools: Bash Read Write Edit
---

# Auto-Workflow: Self-Evolving AI Coding Agent

## Overview

Auto-workflow is an experiment-driven code improvement system that:
1. **Discovers** optimization targets in your Emacs Lisp codebase
2. **Experiments** with code changes using LLM agents
3. **Validates** changes through automated testing
4. **Evolves** its own strategies based on results

## Quick Start

```bash
# Run self-evolution cycle (analyze → evolve skills → experiment)
python3 assistant/skills/auto-workflow/scripts/evolve_skills.py

# Start experiment daemon
emacs --fg-daemon=copilot-auto-workflow
```

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Researcher │────▶│   Analyzer   │────▶│  Experimenter│
│  (external) │     │  (target sel)│     │  (code gen)  │
└─────────────┘     └──────────────┘     └─────────────┘
       │                                        │
       ▼                                        ▼
┌─────────────┐                          ┌──────────────┐
│   Skills    │◀─────────────────────────│   Results    │
│  (evolved)  │                          │   (tracked)  │
└─────────────┘                          └──────────────┘
```

## Key Concepts

### Skills (Self-Evolving)
- **DIRECTIVE.md**: Program definition with target rankings and constraints
- **RESEARCHER.md**: External research instructions with performance metrics
- **RESEARCH.md**: Strategy guide based on downstream experiment success

All skills auto-update after each evolution cycle via `evolve_skills.py`.

### Experiment Pipeline
1. **Target Selection**: Analyzer picks files from `lisp/modules/`
2. **Prompt Building**: Strategy-specific prompt construction
3. **Code Generation**: LLM generates candidate improvements
4. **Validation**: Automated tests check correctness
5. **Grading**: Quality assessment (0-1 score)
6. **Decision**: Keep, discard, or retry
7. **Staging**: Kept changes pushed to staging branch

### Safety Constraints
- Never modifies: `early-init.el`, `pre-early-init.el`, security files
- Never modifies: `eca/`, `mementum/`, `var/elpa/` directories
- Max 10 experiments per target
- 15-minute timeout per experiment

## Commands

### From Emacs
```elisp
;; Start experiment run
M-x gptel-auto-workflow-run

;; Run self-evolution cycle
M-x gptel-auto-workflow-evolution-run-cycle

;; Check status
M-x gptel-auto-workflow-status
```

### From Shell
```bash
# Analyze results and regenerate skills
cd assistant/skills/auto-workflow/scripts
python3 evolve_skills.py --root /path/to/project

# View current directive
cat ../../DIRECTIVE.md

# View researcher skill
cat ../../RESEARCHER.md
```

## Directory Structure

```
assistant/skills/auto-workflow/
├── SKILL.md              # This file
├── DIRECTIVE.md          # Evolving program definition
├── RESEARCHER.md         # External research instructions
├── RESEARCH.md           # Strategy performance guide
├── scripts/
│   ├── evolve_skills.py      # Master evolution script
│   ├── analyze_results.py    # Result parser
│   ├── generate_directive.py # Directive generator
│   └── generate_researcher.py # Researcher generator
└── references/
    └── agentskills-spec.md   # Agent skills specification
```

## Integration with Other Agents

This skill follows the [agentskills.io](https://agentskills.io) standard and can be used by:
- Claude Code
- GitHub Copilot
- OpenCode
- Cursor
- Any agentskills-compatible agent

### For Other Agents
1. Copy `assistant/skills/auto-workflow/` to your agent's skills directory
2. Run `python3 scripts/evolve_skills.py` to initialize
3. The agent will automatically load DIRECTIVE.md and RESEARCHER.md

## Monitoring

Watch these projects for new patterns:
- **hermes-agent**: Agent orchestration
- **zeroclaw**: Lightweight frameworks
- **ml-intern**: ML-powered coding assistants

## Troubleshooting

**Issue**: Experiments timeout
- Check `gptel-auto-workflow-executor-timeout` (default: 900s)
- Verify daemon is running: `ps aux | grep copilot-auto-workflow`

**Issue**: No targets found
- Ensure `lisp/modules/` exists with `.el` files
- Check git repository is initialized

**Issue**: Skills not evolving
- Verify Python 3.8+ is installed
- Check `var/tmp/experiments/` has results.tsv files
- Run `python3 scripts/analyze_results.py` manually

## Metrics

Current performance (auto-updated):
- Total experiments: 870
- Success rate: 13.4% (117 kept)
- Active targets: 36
- Research strategies: Multiple

---

*This skill is part of the minimal-emacs.d ecosystem. It learns from every experiment and adapts its own behavior.*
