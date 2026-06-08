#!/usr/bin/env bash
# install-ops-global.sh - One-shot install of OpenCode Processing Skills + OV5 cowork
# Usage: ./install-ops-global.sh
# Requires: git, opencode with bailian-token-plan and github-copilot providers

set -euo pipefail

REPO_URL="https://github.com/DasDigitaleMomentum/opencode-processing-skills.git"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Detect emacs.d directory (supports non-standard paths)
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
EMACS_DIR="$(cd "$SCRIPT_DIR/.."; pwd)"

# Platform-aware socket path
if [[ "$(uname)" == "Darwin" ]]; then
    OV5_SOCKET="/tmp/emacs$(id -u)/ov5-auto-workflow"
else
    OV5_SOCKET="/run/user/$(id -u)/emacs/ov5-auto-workflow"
fi
SKILL_SRC="${EMACS_DIR}/assistant/skills/ov5"
OPENCODE_SKILLS="${HOME}/.config/opencode/skills/ov5"

echo "=== OpenCode Processing Skills + OV5 Cowork - Global Install ==="

# 1. Clone repo
git clone --depth=1 "$REPO_URL" "$TMPDIR/ops"

# 2. Create config.yaml
cat > "$TMPDIR/ops/config.yaml" <<'EOF'
targets:
  opencode:
    enabled: true
    home: ~/.config/opencode

delegate: bailian-token-plan/deepseek-v4-pro
doc-explorer: bailian-token-plan/deepseek-v4-pro
implementer: bailian-token-plan/glm-5.1
legacy-curator: bailian-token-plan/deepseek-v4-pro

additional_delegates:
  strong:
    model: github-copilot/gpt-5.4
  gpt:
    model: github-copilot/gpt-5.5
    reasoningEffort: max
  opus:
    model: github-copilot/claude-opus-4.8
  qwen:
    model: bailian-token-plan/qwen3.7-max
    reasoningEffort: high
  creative:
    model: bailian-token-plan/deepseek-v4-pro
  fast:
    model: bailian-token-plan/deepseek-v4-flash

additional_implementers:
  safe:
    model: bailian-token-plan/qwen3.6-plus
EOF

# 3. Cross-platform text edits use perl5 (perl -pi -e works on macOS + Linux)
# No BSD/GNU sed wrapper needed: perl is identical on both platforms.
if [[ "$(uname)" == "Darwin" ]]; then
    echo "Using perl5 for cross-platform text edits (macOS)"
fi

# 4. Run installer
cd "$TMPDIR/ops" && bash install.sh || echo "WARNING: install.sh failed, continuing with model fixes"

# 5. Fix models in agent files
AGENTS_DIR="$HOME/.config/opencode/agents"

update_model() {
    local file="$1" model="$2"
    if [ -f "$file" ]; then
        perl -pi -e 's|^model:.*|model: '"$model"'|' "$file"
    fi
}

# Primary
for agent in maintainer maintainer-direct; do
    file="$AGENTS_DIR/$agent.md"
    if [ -f "$file" ]; then
        # Portable: remove any existing model line, then insert after description.
        # perl -i -pe applies the block to each line; $_ holds the current line.
        perl -i -pe 'if (/^model:/) { $_ = ""; } elsif (/^description:/) { $_ = $_ . "model: bailian-token-plan/kimi-k2.6\n"; }' "$file"
    fi
done

# Subagents
update_model "$AGENTS_DIR/delegate.md"             "bailian-token-plan/deepseek-v4-pro"
update_model "$AGENTS_DIR/delegate-fast.md"          "bailian-token-plan/deepseek-v4-flash"
update_model "$AGENTS_DIR/delegate-strong.md"        "github-copilot/gpt-5.4"
update_model "$AGENTS_DIR/delegate-gpt.md"           "github-copilot/gpt-5.5"
update_model "$AGENTS_DIR/delegate-opus.md"          "github-copilot/claude-opus-4.8"
update_model "$AGENTS_DIR/delegate-qwen.md"          "bailian-token-plan/qwen3.7-max"
update_model "$AGENTS_DIR/delegate-creative.md"      "bailian-token-plan/deepseek-v4-pro"
update_model "$AGENTS_DIR/doc-explorer.md"           "bailian-token-plan/deepseek-v4-pro"
update_model "$AGENTS_DIR/implementer.md"           "bailian-token-plan/glm-5.1"
update_model "$AGENTS_DIR/implementer-safe.md"      "bailian-token-plan/qwen3.6-plus"
update_model "$AGENTS_DIR/legacy-curator.md"        "bailian-token-plan/deepseek-v4-pro"

# 6. Enable thinking for DeepSeek models in opencode.json (pure jq, no python3)
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
if [ -f "$OPENCODE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        tmp_json="$(mktemp)"
        jq '
          .provider["bailian-token-plan"].models["deepseek-v4-pro"].options.thinking = {"type": "enabled", "budgetTokens": 16384} |
          .provider["bailian-token-plan"].models["deepseek-v4-flash"].options.thinking = {"type": "enabled", "budgetTokens": 16384}
        ' "$OPENCODE_JSON" > "$tmp_json" && mv "$tmp_json" "$OPENCODE_JSON"
        echo "DeepSeek thinking enabled (via jq)"
    else
        echo "WARNING: jq not found — skip enabling DeepSeek thinking mode"
        echo "Install jq or manually add thinking config to $OPENCODE_JSON"
    fi
fi

# 7. OV5 Cowork Setup — OpenCode only
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

echo ""
echo "=== OV5 Cowork Setup ==="

# 7a. OpenCode skill
mkdir -p "${OPENCODE_SKILLS}"
if [[ -f "${SKILL_SRC}/SKILL.md" ]]; then
    cp "${SKILL_SRC}/SKILL.md" "${OPENCODE_SKILLS}/SKILL.md"
    echo "OpenCode skill → ${OPENCODE_SKILLS}/SKILL.md"
else
    echo "WARNING: SKILL.md not found at ${SKILL_SRC}"
fi

# 7b. Write cowork instructions with runtime-specific paths
if [[ -n "${COWORK_INSTRUCTIONS}" ]]; then
    echo "${COWORK_INSTRUCTIONS}" > "${OPENCODE_SKILLS}/COWORK.md"
    echo "Cowork instructions → ${OPENCODE_SKILLS}/COWORK.md"
fi

echo ""
echo "=== Installation Complete ==="
echo "Models: @maintainer→kimi-k2.6, delegate→deepseek-v4-pro, strong→gpt-5.4, gpt→gpt-5.5, opus→claude-opus-4.8, qwen→qwen3.7-max, creative→deepseek-v4-pro, fast→deepseek-v4-flash, implementer→glm-5.1, implementer-safe→qwen3.6-plus"
echo "OV5 Cowork: OpenCode configured"
echo "Next: Restart OpenCode, select @maintainer agent"
