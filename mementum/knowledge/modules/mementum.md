# Mementum Module

## Purpose

Bridges auto-workflow experiments with the mementum memory system. Creates atomic memories per experiment and synthesizes them into knowledge pages for prompt injection.

## Architecture

```
Experiment results ──→ Memories ──→ Knowledge synthesis ──→ Prompt injection
     ↓                    ↓              ↓                      ↓
  TSV + Git         mementum/      Weekly batch          Executor +
                     memories/      job updates           Analyzer
                   knowledge/
```

## Key Functions

| Function | Purpose |
|---|---|
| `gptel-auto-workflow--mementum-record` | Store experiment result as atomic memory |
| `gptel-auto-workflow--mementum-synthesize` | Batch synthesize memories → knowledge pages |
| `gptel-auto-workflow--mementum-recall` | Recall context for prompt injection |
| `gptel-auto-workflow--mementum-store` | Store insight with validation |

## Configuration

```elisp
(defvar gptel-auto-workflow-mementum-enabled t)
(defvar gptel-auto-workflow-mementum-dir "mementum")
(defvar gptel-auto-workflow-mementum-memory-dir "mementum/memories")
(defvar gptel-auto-workflow-mementum-knowledge-dir "mementum/knowledge")
```

## Symbol Map

| Symbol | Meaning |
|---|---|
| 💡 | insight |
| ❌ | mistake |
| ✅ | win |
| 🔄 | shift |
| 🎯 | decision |
| 🌀 | meta |
| 🔁 | pattern |

## Integration Points

- **Evolution**: `gptel-auto-workflow-evolution` reads synthesized knowledge
- **Pipeline**: Auto-stores after each experiment
- **Research**: Auto-stores findings
- **Self-Heal**: Stores fix patterns
