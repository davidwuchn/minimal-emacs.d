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

OV5_SOCKET="/run/user/$(id -u)/emacs/ov5-auto-workflow"
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
    model: bailian-token-plan/kimi-k2.6
  fast:
    model: bailian-token-plan/deepseek-v4-flash

additional_implementers:
  safe:
    model: bailian-token-plan/glm-5.1
EOF

# 3. Ensure GNU sed on macOS (BSD sed is incompatible with install.sh)
if [[ "$(uname)" == "Darwin" ]] && ! command -v gsed >/dev/null 2>&1; then
    # Create a sed wrapper that handles GNU-only features
    SED_WRAP_DIR="$(mktemp -d)"
    cat > "$SED_WRAP_DIR/sed" <<'SEDWRAP'
#!/usr/bin/env bash
set -euo pipefail
in_place=false
script=""
files=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -i) in_place=true; shift
             if [[ $# -gt 0 && "$1" != -* && "$1" != /* && "$1" != s* ]]; then shift; fi ;;
        -*) echo "sed-wrapper: unknown option: $1" >&2; exit 1 ;;
        *)  if [[ -z "$script" ]]; then script="$1"; else files+=("$1"); fi; shift ;;
    esac
done

# Handle GNU inline 'a' (append) command via awk
if [[ "$script" =~ ^/(.+)/a[[:space:]](.+)$ ]]; then
    pattern="${BASH_REMATCH[1]}"
    text="${BASH_REMATCH[2]}"
    for file in "${files[@]}"; do
        if $in_place && [[ -n "$file" && -f "$file" ]]; then
            tmpf="$(mktemp)"
            awk -v t="$text" "/${pattern}/{print; print t; next}1" "$file" > "$tmpf" && mv "$tmpf" "$file"
        elif [[ -n "$file" && -f "$file" ]]; then
            awk -v t="$text" "/${pattern}/{print; print t; next}1" "$file"
        fi
    done
    exit 0
fi

# Pass through to BSD sed (with -i '' fix)
bsd_args=()
$in_place && bsd_args+=("-i" "")
[[ -n "$script" ]] && bsd_args+=("$script")
bsd_args+=("${files[@]}")
exec /usr/bin/sed "${bsd_args[@]}"
SEDWRAP
    chmod +x "$SED_WRAP_DIR/sed"
    export PATH="$SED_WRAP_DIR:$PATH"
    trap 'rm -rf "$SED_WRAP_DIR" "$TMPDIR"' EXIT
    echo "Using BSD sed compatibility wrapper"
elif [[ "$(uname)" == "Darwin" ]]; then
    # gsed is available — prepend gnubin to use GNU sed everywhere
    GNUBIN="$(brew --prefix gnu-sed)/libexec/gnubin"
    export PATH="$GNUBIN:$PATH"
    echo "Using GNU sed ($GNUBIN)"
fi

# 4. Run installer
cd "$TMPDIR/ops" && bash install.sh || echo "WARNING: install.sh failed, continuing with model fixes"

# 5. Fix models in agent files
AGENTS_DIR="$HOME/.config/opencode/agents"

update_model() {
    local file="$1" model="$2"
    if [ -f "$file" ]; then
        local tmpf
        tmpf="$(mktemp)"
        sed "s|^model:.*|model: $model|" "$file" > "$tmpf" && mv "$tmpf" "$file"
    fi
}

# Primary
for agent in maintainer maintainer-direct; do
    file="$AGENTS_DIR/$agent.md"
    if [ -f "$file" ]; then
        # Portable: delete model line, then insert after description using temp file
        tmpf="$(mktemp)"
        sed '/^model:/d' "$file" > "$tmpf"
        # Insert "model: ..." after the description line
        awk '/^description:/{print; print "model: bailian-token-plan/kimi-k2.6"; next}1' "$tmpf" > "$file"
        rm -f "$tmpf"
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

echo ""
echo "=== Installation Complete ==="
echo "Models: @maintainer→kimi-k2.6, delegate→deepseek-v4-pro, strong→gpt-5.4, gpt→gpt-5.5, opus→claude-opus-4.8, qwen→qwen3.7-max, creative→kimi-k2.6, fast→deepseek-v4-flash, implementer→glm-5.1"
echo "OV5 Cowork: OpenCode configured"
echo "Next: Restart OpenCode, select @maintainer agent"
