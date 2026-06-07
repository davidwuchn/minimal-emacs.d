# LLM Output Sanitization

**Category**: defect-prevention
**Date**: 2026-06-07

## Insight

Raw LLM responses from `gptel-request` callbacks can contain internal Lisp structs like `(tool-result (#s(gptel-tool ...)))` instead of human-readable text. These must NEVER be inserted into prompts or knowledge files unsanitized.

## Pattern

All gptel-request callback responses should pass through `gptel-auto-workflow--sanitize-llm-output` before being:
- Inserted into knowledge markdown files (mementum/knowledge/*.md)
- Written to research insights or Allium issues files
- Loaded back into prompts (strategy proposer, etc.)

The sanitizer detects `(tool-result`, `(#s(gptel-tool`, `#s(` patterns and replaces with a count-based summary.

## Fixed Locations (2026-06-07)

1. `gptel-auto-workflow-evolution.el` - allium-persist-spec (issues file + knowledge page)
2. `gptel-auto-workflow-evolution.el` - allium-load-issues-for-guidance (prompt injection path)
3. `gptel-auto-workflow-mementum.el` - mementum-record-research (findings + digested)
4. `gptel-tools-agent-research.el` - save-knowledge-page (LLM synthesis)

## Lesson

gptel callbacks return whatever the LLM emits, including tool validation output. Never trust raw response text for persistence or prompt assembly.
