#!/usr/bin/env bash
# install-ops-global.sh - One-shot install of OpenCode Processing Skills + OV5 cowork
# Usage: ./install-ops-global.sh
# Requires: git, opencode with deepseek and github-copilot providers

set -euo pipefail

REPO_URL="https://github.com/DasDigitaleMomentum/opencode-processing-skills.git"
OPS_REF="${OPS_REF:-main}"   # allow override: OPS_REF=v1.2.3 ./install-ops-global.sh
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Detect emacs.d directory (supports non-standard paths)
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
EMACS_DIR="$(cd "$SCRIPT_DIR/.."; pwd)"

# Socket path: detect systemd runtime dir first, fall back to /tmp
if [ -d "/run/user/$(id -u)/emacs" ]; then
    OV5_SOCKET="/run/user/$(id -u)/emacs/ov5-auto-workflow"
elif [ -S "/tmp/emacs$(id -u)/ov5-auto-workflow" ]; then
    OV5_SOCKET="/tmp/emacs$(id -u)/ov5-auto-workflow"
else
    OV5_SOCKET="/tmp/emacs$(id -u)/ov5-auto-workflow"
fi
SKILL_SRC="${EMACS_DIR}/assistant/skills/ov5"
OPENCODE_SKILLS="${HOME}/.config/opencode/skills/ov5"

echo "=== OpenCode Processing Skills + OV5 Cowork - Global Install ==="

# 1. Clone repo
git clone --depth=1 --branch "$OPS_REF" "$REPO_URL" "$TEMP_DIR/ops"

# 2. Create config.yaml
cat > "$TEMP_DIR/ops/config.yaml" <<'EOF'
targets:
  opencode:
    enabled: true
    home: ~/.config/opencode

delegate: deepseek/deepseek-v4-pro
doc-explorer: deepseek/deepseek-v4-pro
implementer: deepseek/deepseek-v4-pro
legacy-curator: deepseek/deepseek-v4-pro

additional_delegates:
  strong:
    model: github-copilot/gpt-5.4
    reasoningEffort: xhigh
  gpt:
    model: github-copilot/gpt-5.5
    reasoningEffort: max
  opus:
    model: github-copilot/claude-opus-4.8
  qwen:
    model: deepseek/deepseek-v4-pro
    reasoningEffort: high
  creative:
    model: deepseek/deepseek-v4-pro
  fast:
    model: deepseek/deepseek-v4-flash

additional_implementers:
  safe:
    model: github-copilot/gpt-5.4-mini
    reasoningEffort: xhigh
EOF

# 3. Cross-platform text edits use perl5 (perl -pi -e works on macOS + Linux)
# No BSD/GNU sed wrapper needed: perl is identical on both platforms.
if [[ "$(uname)" == "Darwin" ]]; then
    echo "Using perl5 for cross-platform text edits (macOS)"
fi

# 4. Run installer
if ! cd "$TEMP_DIR/ops" && bash install.sh; then
    echo "ERROR: OPS install.sh failed. Aborting to avoid corrupting agent configs."
    echo "Check output above or retry with: OPS_REF=<known-good-tag> $0"
    exit 1
fi

# 5. Fix models in agent files
AGENTS_DIR="$HOME/.config/opencode/agents"
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"

# 5a. Backup before any modification
BACKUP_DIR="$HOME/.config/opencode/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp -r "$AGENTS_DIR" "$BACKUP_DIR/"
[ -f "$OPENCODE_JSON" ] && cp "$OPENCODE_JSON" "$BACKUP_DIR/"
echo "Backup created: $BACKUP_DIR"

update_model() {
    local file="$1" model="$2"
    if [ -f "$file" ]; then
        # Only touch model: inside frontmatter (before second '---')
        perl -i -pe '
            if (/^---/) { $fm++; }
            if ($fm < 2 && /^model:/) { $_ = "model: '"$model"'\n"; }
        ' "$file"
    fi
}

# Primary
for agent in maintainer maintainer-direct; do
    file="$AGENTS_DIR/$agent.md"
    if [ -f "$file" ]; then
        # Remove existing model line (frontmatter only)
        perl -i -pe 'if (/^---/) { $fm++; } if ($fm < 2 && /^model:/) { $_ = ""; }' "$file"
        # Insert model after description; avoid duplicating options block
        if grep -q "^options:" "$file"; then
            perl -pi -e 'if (/^description:/) { $_ = $_ . "model: deepseek/deepseek-v4-pro\n"; }' "$file"
        else
            perl -pi -e 'if (/^description:/) { $_ = $_ . "model: deepseek/deepseek-v4-pro\noptions:\n  reasoningEffort: high\n"; }' "$file"
        fi
    fi
done

# Subagents
update_model "$AGENTS_DIR/delegate.md"             "deepseek/deepseek-v4-pro"
update_model "$AGENTS_DIR/delegate-fast.md"          "deepseek/deepseek-v4-flash"
# delegate-strong — ensure reasoningEffort: xhigh
if [ -f "$AGENTS_DIR/delegate-strong.md" ]; then
    perl -pi -e 's|^model:.*|model: github-copilot/gpt-5.4|' "$AGENTS_DIR/delegate-strong.md"
    if ! grep -q "^options:" "$AGENTS_DIR/delegate-strong.md"; then
        perl -pi -e 's|^(model: github-copilot/gpt-5.4)$|$1\noptions:\n  reasoningEffort: xhigh|' "$AGENTS_DIR/delegate-strong.md"
    else
        perl -pi -e 's|^  reasoningEffort:.*|  reasoningEffort: xhigh|' "$AGENTS_DIR/delegate-strong.md"
    fi
fi
update_model "$AGENTS_DIR/delegate-gpt.md"           "github-copilot/gpt-5.5"
update_model "$AGENTS_DIR/delegate-opus.md"          "github-copilot/claude-opus-4.8"
# delegate-qwen — restore meaningful description (OPS overwrites with generic)
if [ -f "$AGENTS_DIR/delegate-qwen.md" ]; then
    perl -pi -e 's|^description:.*|description: Delegate variant '"'"'qwen'"'"' with model deepseek/deepseek-v4-pro. Use for second opinions, cross-checking results, Chinese language tasks, and alternative perspectives on hard problems.|' "$AGENTS_DIR/delegate-qwen.md"
    update_model "$AGENTS_DIR/delegate-qwen.md" "deepseek/deepseek-v4-pro"
fi
# delegate-creative — also fix stale description referencing minimax-cn-coding-plan
if [ -f "$AGENTS_DIR/delegate-creative.md" ]; then
    perl -pi -e 's|^description:.*|description: Delegate variant '"'"'creative'"'"' with model deepseek/deepseek-v4-pro. Use for creative writing, brainstorming, content generation, and open-ended exploration.|' "$AGENTS_DIR/delegate-creative.md"
    update_model "$AGENTS_DIR/delegate-creative.md" "deepseek/deepseek-v4-pro"
fi
update_model "$AGENTS_DIR/doc-explorer.md"           "deepseek/deepseek-v4-pro"
update_model "$AGENTS_DIR/implementer.md"           "deepseek/deepseek-v4-pro"
# implementer-safe — ensure reasoningEffort: xhigh
if [ -f "$AGENTS_DIR/implementer-safe.md" ]; then
    perl -pi -e 's|^model:.*|model: github-copilot/gpt-5.4-mini|' "$AGENTS_DIR/implementer-safe.md"
    if ! grep -q "^options:" "$AGENTS_DIR/implementer-safe.md"; then
        perl -pi -e 's|^(model: github-copilot/gpt-5.4-mini)$|$1\noptions:\n  reasoningEffort: xhigh|' "$AGENTS_DIR/implementer-safe.md"
    else
        perl -pi -e 's|^  reasoningEffort:.*|  reasoningEffort: xhigh|' "$AGENTS_DIR/implementer-safe.md"
    fi
fi
update_model "$AGENTS_DIR/legacy-curator.md"        "deepseek/deepseek-v4-pro"

# 5b. Warn about unhandled delegate-* agents
for f in "$AGENTS_DIR"/delegate-*.md; do
    [ -f "$f" ] || continue
    agent=$(basename "$f" .md)
    case "$agent" in
        delegate|delegate-fast|delegate-strong|delegate-gpt|delegate-opus|delegate-qwen|delegate-creative) ;;
        *) echo "NOTE: Unhandled agent $f — verify model manually" ;;
    esac
done

# 6. Set compaction and small model in opencode.json (pure jq, no python3)
if [ -f "$OPENCODE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        tmp_json="$(mktemp)"
        jq '
          .small_model = "deepseek/deepseek-v4-flash" |
          .agent.compaction.model = "deepseek/deepseek-v4-flash"
        ' "$OPENCODE_JSON" > "$tmp_json" && mv "$tmp_json" "$OPENCODE_JSON"
        echo "Compaction + small_model set to deepseek/deepseek-v4-flash (via jq)"
    else
        echo "WARNING: jq not found — skip setting compaction model"
        echo "Install jq or manually add compaction config to $OPENCODE_JSON"
    fi
fi

# 6b. Validate agent frontmatter after edits (perl5, no python3)
perl -e '
use strict;
use warnings;
for my $f (@ARGV) {
    open my $fh, "<", $f or next;
    my $text = do { local $/; <$fh> };
    close $fh;
    if ($text =~ /^---\n(.*?)\n---/s) {
        my $fm = $1;
        my %keys;
        while ($fm =~ /^(\w+):/mg) {
            if ($keys{$1}++) {
                print "WARNING: $f has duplicate key $1 in frontmatter\n";
            }
        }
        # Check for unclosed quotes (count occurrences)
        my $squote = () = $fm =~ /\x27/g;
        my $dquote = () = $fm =~ /\x22/g;
        if ($squote % 2 != 0 || $dquote % 2 != 0) {
            print "WARNING: $f has unclosed quotes in frontmatter\n";
        }
    } else {
        print "WARNING: $f missing frontmatter delimiters\n";
    }
}
' "$AGENTS_DIR"/*.md 2>/dev/null || true

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
- \`tail ${EMACS_DIR}/var/log/emacs-*.log | grep -E 'kept|discard|RESULT'\`
- \`cat ${EMACS_DIR}/var/tmp/experiments/*/results.tsv | column -t\`
- \`git -C ${EMACS_DIR} log --oneline -10\`

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
echo "Models: @maintainer→deepseek/deepseek-v4-pro, delegate→deepseek/deepseek-v4-pro, strong→gpt-5.4, gpt→gpt-5.5, opus→claude-opus-4.8, qwen→deepseek/deepseek-v4-pro, creative→deepseek/deepseek-v4-pro, fast→deepseek/deepseek-v4-flash, implementer→deepseek/deepseek-v4-pro, implementer-safe→gpt-5.4-mini"
echo "OV5 Cowork: OpenCode configured"
echo "Next: Restart OpenCode, select @maintainer agent"
