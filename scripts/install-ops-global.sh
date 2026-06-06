#!/usr/bin/env bash
# install-ops-global.sh - One-shot install of OpenCode Processing Skills
# Usage: ./install-ops-global.sh
# Requires: git, opencode with bailian-token-plan and github-copilot providers

set -euo pipefail

REPO_URL="https://github.com/DasDigitaleMomentum/opencode-processing-skills.git"
TMPDIR="$(mktemp -d)"
trap "rm -rf $TMPDIR" EXIT

echo "=== OpenCode Processing Skills - Global Install ==="

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
    model: bailian-token-plan/kimi-k2.6
  fast:
    model: bailian-token-plan/deepseek-v4-flash

additional_implementers:
  safe:
    model: bailian-token-plan/glm-5.1
EOF

# 3. Run installer
cd "$TMPDIR/ops" && bash install.sh 2>/dev/null || true

# 4. Fix models in agent files
AGENTS_DIR="$HOME/.config/opencode/agents"

update_model() {
    local file="$1" model="$2"
    [ -f "$file" ] && sed -i.bak "s/^model:.*/model: $model/" "$file" && rm -f "$file.bak"
}

# Primary
for agent in maintainer maintainer-direct; do
    file="$AGENTS_DIR/$agent.md"
    if [ -f "$file" ]; then
        sed -i.bak '/^model:/d' "$file"
        sed -i.bak '/^description:/a\model: bailian-token-plan/kimi-k2.6' "$file"
        rm -f "$file.bak"
    fi
done

# Subagents
update_model "$AGENTS_DIR/delegate.md"             "bailian-token-plan/deepseek-v4-pro"
update_model "$AGENTS_DIR/delegate-fast.md"          "bailian-token-plan/deepseek-v4-flash"
update_model "$AGENTS_DIR/delegate-strong.md"        "github-copilot/gpt-5.4"
update_model "$AGENTS_DIR/delegate-gpt.md"           "github-copilot/gpt-5.5"
update_model "$AGENTS_DIR/delegate-opus.md"          "github-copilot/claude-opus-4.8"
update_model "$AGENTS_DIR/delegate-qwen.md"          "bailian-token-plan/qwen3.7-max"
update_model "$AGENTS_DIR/delegate-creative.md"      "bailian-token-plan/kimi-k2.6"
update_model "$AGENTS_DIR/doc-explorer.md"           "bailian-token-plan/deepseek-v4-pro"
update_model "$AGENTS_DIR/implementer.md"           "bailian-token-plan/glm-5.1"
update_model "$AGENTS_DIR/implementer-safe.md"      "bailian-token-plan/glm-5.1"
update_model "$AGENTS_DIR/legacy-curator.md"        "bailian-token-plan/deepseek-v4-pro"

# 5. Enable thinking for DeepSeek models in opencode.json
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
if [ -f "$OPENCODE_JSON" ] && command -v python3 >/dev/null; then
    python3 -c "
import json, os
with open('$OPENCODE_JSON', 'r') as f:
    data = json.load(f)
provider = data.get('provider', {}).get('bailian-token-plan', {})
models = provider.get('models', {})
for model_name in ['deepseek-v4-pro', 'deepseek-v4-flash']:
    if model_name in models:
        if 'options' not in models[model_name]:
            models[model_name]['options'] = {}
        models[model_name]['options']['thinking'] = {
            'type': 'enabled',
            'budgetTokens': 16384
        }
with open('$OPENCODE_JSON', 'w') as f:
    json.dump(data, f, indent=2)
print('DeepSeek thinking enabled')
" 2>/dev/null || true
fi

echo ""
echo "=== Installation Complete ==="
echo "Models: @maintainer→kimi-k2.6, delegate→deepseek-v4-pro, strong→gpt-5.4, gpt→gpt-5.5, opus→claude-opus-4.8, qwen→qwen3.7-max, creative→kimi-k2.6, fast→deepseek-v4-flash, implementer→glm-5.1"
echo "Next: Restart OpenCode, select @maintainer agent"
