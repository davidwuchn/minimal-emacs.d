#!/usr/bin/env bash
# Setup OV5 cowork skill for AI coding agents.
# Supports: OpenCode, Claude Code, Cursor, and MCP-compatible agents.

set -euo pipefail

EMACS_DIR="${HOME}/.emacs.d"
OV5_SOCKET="/run/user/$(id -u)/emacs/ov5-auto-workflow"
SKILL_SRC="${EMACS_DIR}/assistant/skills/ov5"
OPENCODE_SKILLS="${HOME}/.config/opencode/skills/ov5"
CLAUDE_MD="${EMACS_DIR}/CLAUDE.md"
CURSOR_RULES="${EMACS_DIR}/.cursorrules"
# Shared OV5 cowork instructions for agents.
COWORK_INSTRUCTIONS="# OV5

OV5 is a self-evolving Emacs daemon that runs automated code improvement experiments.
Communicate with it via \`emacsclient\`.

Socket: ${OV5_SOCKET}

## Key commands
- \`(gptel-auto-workflow-status)\` — pipeline phase, targets, keep-rate
- \`(gptel-auto-workflow-run-async)\` — trigger a new experiment cycle
- \`(gptel-auto-workflow--running)\` — is pipeline active?
- \`(gptel-auto-workflow--rate-limited-backends)\` — which providers are rate-limited
- \`(gptel-auto-workflow--current-target)\` — file being experimented on

## Results
- \`tail ~/.emacs.d/var/log/emacs-*.log | grep -E \"kept|discard|RESULT\"\`
- \`cat ~/.emacs.d/var/tmp/experiments/*/results.tsv | column -t\`
- \`git -C ~/.emacs.d log --oneline -10\`

## Coworking pattern
1. Review code, identify improvement
2. Request experiment: \`(gptel-auto-workflow-run-async)\`
3. OV5 runs experiment in isolated worktree (~30min)
4. Review results: check git log + results.tsv
5. Merge or refine — ontology learns from every outcome
"

echo "=== Setting up OV5 cowork integration ==="

# 1. OpenCode skill
echo ""
echo "[1/4] OpenCode skill..."
mkdir -p "${OPENCODE_SKILLS}"
if [[ -f "${SKILL_SRC}/SKILL.md" ]]; then
  cp "${SKILL_SRC}/SKILL.md" "${OPENCODE_SKILLS}/SKILL.md"
  echo "  Copied skill to ${OPENCODE_SKILLS}/SKILL.md"
elif [[ -f "${HOME}/.config/opencode/skills/ov5/SKILL.md" ]]; then
  echo "  Already exists at ${HOME}/.config/opencode/skills/ov5/SKILL.md"
else
  echo "  warning: SKILL.md not found at ${SKILL_SRC} or ~/.config/opencode/skills/ov5/"
  echo "  Create ~/.config/opencode/skills/ov5/SKILL.md manually (see assistant/skills/auto-workflow/)"
fi

# 2. Claude Code (CLAUDE.md)
echo ""
echo "[2/4] Claude Code (CLAUDE.md)..."
if [[ ! -f "${CLAUDE_MD}" ]] || ! grep -q "OV5" "${CLAUDE_MD}" 2>/dev/null; then
  echo "${COWORK_INSTRUCTIONS}" >> "${CLAUDE_MD}"
  echo "  Appended to ${CLAUDE_MD}"
else
  echo "  Already has OV5 instructions"
fi

# 3. Cursor (.cursorrules)
echo ""
echo "[3/4] Cursor (.cursorrules)..."
if [[ ! -f "${CURSOR_RULES}" ]] || ! grep -q "OV5" "${CURSOR_RULES}" 2>/dev/null; then
  echo "${COWORK_INSTRUCTIONS}" >> "${CURSOR_RULES}"
  echo "  Appended to ${CURSOR_RULES}"
else
  echo "  Already has OV5 instructions"
fi

echo ""
echo "=== Setup complete ==="
echo "Restart your coding agent to pick up the new skill."
