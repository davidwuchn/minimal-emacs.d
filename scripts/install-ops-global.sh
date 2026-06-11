#!/usr/bin/env bash
# install-ops-global.sh - One-shot install of OpenCode Processing Skills + OV5 cowork
# Usage: ./install-ops-global.sh
# Requires: git, perl, opencode with deepseek and github-copilot providers

set -euo pipefail

REPO_URL="https://github.com/DasDigitaleMomentum/opencode-processing-skills.git"
OPS_REF="${OPS_REF:-main}"   # allow override: OPS_REF=v1.2.3 ./install-ops-global.sh
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Detect emacs.d directory (supports non-standard paths)
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
EMACS_DIR="$(cd "$SCRIPT_DIR/.."; pwd)"

# Preflight dependency checks
for cmd in git perl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "ERROR: Required command '$cmd' not found. Install it first." >&2
        exit 1
    fi
done

# Socket path: /tmp/emacs$UID/ per AGENTS.md S3
OV5_SOCKET="/tmp/emacs$(id -u)/pmf-value-stream"
# 8. OV5 Cowork Setup — skill installation
# Skills live in assistant/skills/ (OV5 evolves them there).
# opencode loads them via .opencode/skills/ symlinks (if in repo) or
# ~/.config/opencode/skills/ copies (if standalone).

SKILLS_TO_INSTALL="ov5 brepl daemon-repl"
LOCAL_SKILLS_DIR="${EMACS_DIR}/.opencode/skills"
GLOBAL_SKILLS_DIR="${HOME}/.config/opencode/skills"

echo ""
echo "=== OV5 Cowork Setup ==="

for skill in $SKILLS_TO_INSTALL; do
    SKILL_SRC="${EMACS_DIR}/assistant/skills/${skill}/SKILL.md"
    if [[ ! -f "${SKILL_SRC}" ]]; then
        echo "WARNING: ${skill}/SKILL.md not found at ${SKILL_SRC}"
        continue
    fi

    # Check if already installed via .opencode/skills/ symlink (repo-local)
    if [[ -L "${LOCAL_SKILLS_DIR}/${skill}" ]]; then
        echo "${skill}: already symlinked in .opencode/skills/ → $(readlink "${LOCAL_SKILLS_DIR}/${skill}")"
        continue
    fi

    # Check if already installed as real directory in .opencode/skills/
    if [[ -d "${LOCAL_SKILLS_DIR}/${skill}" ]]; then
        echo "${skill}: already exists in .opencode/skills/ (not symlink — consider converting)"
        continue
    fi

    # Check if already installed in global ~/.config/opencode/skills/
    if [[ -f "${GLOBAL_SKILLS_DIR}/${skill}/SKILL.md" ]]; then
        echo "${skill}: already installed in ${GLOBAL_SKILLS_DIR}/${skill}/"
        continue
    fi

    # Install: prefer repo-local symlink, fall back to global copy
    if [[ -d "${LOCAL_SKILLS_DIR}" ]]; then
        ln -s "../../assistant/skills/${skill}" "${LOCAL_SKILLS_DIR}/${skill}"
        echo "${skill}: symlinked .opencode/skills/${skill} → assistant/skills/${skill}"
    else
        mkdir -p "${GLOBAL_SKILLS_DIR}/${skill}"
        cp "${SKILL_SRC}" "${GLOBAL_SKILLS_DIR}/${skill}/SKILL.md"
        echo "${skill}: copied → ${GLOBAL_SKILLS_DIR}/${skill}/SKILL.md"
    fi
done

echo ""
echo "=== Installation Complete ==="

# 1. Clone repo
echo "Cloning opencode-processing-skills ($OPS_REF)..."
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
    reasoningEffort: xhigh
  opus:
    model: github-copilot/claude-opus-4.8
  qwen:
    model: deepseek/deepseek-v4-pro
    reasoningEffort: high
  creative:
    model: deepseek/deepseek-v4-pro
    reasoningEffort: high
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

# 4. Backup BEFORE running external installer
AGENTS_DIR="$HOME/.config/opencode/agents"
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
BACKUP_DIR="$HOME/.config/opencode/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
[ -d "$AGENTS_DIR" ] && cp -R "$AGENTS_DIR" "$BACKUP_DIR/"
[ -f "$OPENCODE_JSON" ] && cp "$OPENCODE_JSON" "$BACKUP_DIR/"
echo "Backup created: $BACKUP_DIR"

# 5. Run installer (fixed: use explicit path, not cd+&&)
echo "Running OPS install.sh..."
if ! bash "$TEMP_DIR/ops/install.sh"; then
    echo "ERROR: OPS install.sh failed. Backup at: $BACKUP_DIR" >&2
    echo "Restore with: cp -R '$BACKUP_DIR/agents' '$AGENTS_DIR'" >&2
    echo "Retry with: OPS_REF=<known-good-tag> $0" >&2
    exit 1
fi

# 6. Fix models in agent files

# Helper: update model: line in frontmatter only (before second ---)
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

# Helper: scope grep to frontmatter only
fm_grep() {
    local file="$1" pattern="$2"
    # Extract frontmatter (between first two ---) and grep within it
    perl -ne 'BEGIN { $fm = 0; $found = 0; } if (/^---/) { $fm++; } if ($fm == 1 && /'"$pattern"'/) { $found = 1; } END { exit($found ? 0 : 1); }' "$file"
}

# Primary
for agent in maintainer maintainer-direct; do
    file="$AGENTS_DIR/$agent.md"
    if [ -f "$file" ]; then
        # Remove existing model line (frontmatter only)
        perl -i -pe 'if (/^---/) { $fm++; } if ($fm < 2 && /^model:/) { $_ = ""; }' "$file"
        # Insert model after description; avoid duplicating options block
        if fm_grep "$file" "^options:"; then
            perl -pi -e 'if (/^description:/) { $_ = $_ . "model: deepseek/deepseek-v4-pro\n"; }' "$file"
        else
            perl -pi -e 'if (/^description:/) { $_ = $_ . "model: deepseek/deepseek-v4-pro\noptions:\n  reasoningEffort: high\n"; }' "$file"
        fi
    fi
done

# Subagents
update_model "$AGENTS_DIR/delegate.md"             "deepseek/deepseek-v4-pro"
# delegate — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/delegate.md" ]; then
    if ! fm_grep "$AGENTS_DIR/delegate.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate.md"
    fi
fi
update_model "$AGENTS_DIR/delegate-fast.md"          "deepseek/deepseek-v4-flash"
# delegate-fast — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/delegate-fast.md" ]; then
    if ! fm_grep "$AGENTS_DIR/delegate-fast.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-fast.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-fast.md"
    fi
fi
# delegate-strong — ensure reasoningEffort: xhigh
if [ -f "$AGENTS_DIR/delegate-strong.md" ]; then
    perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model:/) { $_ = "model: github-copilot/gpt-5.4\n"; }' "$AGENTS_DIR/delegate-strong.md"
    if ! fm_grep "$AGENTS_DIR/delegate-strong.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: github-copilot/) { $_ .= "options:\n  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/delegate-strong.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/delegate-strong.md"
    fi
fi
update_model "$AGENTS_DIR/delegate-gpt.md"           "github-copilot/gpt-5.5"
# delegate-gpt — ensure reasoningEffort: xhigh
if [ -f "$AGENTS_DIR/delegate-gpt.md" ]; then
    if ! fm_grep "$AGENTS_DIR/delegate-gpt.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: github-copilot/) { $_ .= "options:\n  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/delegate-gpt.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/delegate-gpt.md"
    fi
fi
update_model "$AGENTS_DIR/delegate-opus.md"          "github-copilot/claude-opus-4.8"
# delegate-opus — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/delegate-opus.md" ]; then
    if ! fm_grep "$AGENTS_DIR/delegate-opus.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: github-copilot/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-opus.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-opus.md"
    fi
fi
# delegate-qwen — restore meaningful description + ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/delegate-qwen.md" ]; then
    perl -pi -e 's|^description:.*|description: Delegate variant '"'"'qwen'"'"' with model deepseek/deepseek-v4-pro. Use for second opinions, cross-checking results, Chinese language tasks, and alternative perspectives on hard problems.|' "$AGENTS_DIR/delegate-qwen.md"
    update_model "$AGENTS_DIR/delegate-qwen.md" "deepseek/deepseek-v4-pro"
    if ! fm_grep "$AGENTS_DIR/delegate-qwen.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-qwen.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-qwen.md"
    fi
fi
# delegate-creative — fix stale description + ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/delegate-creative.md" ]; then
    perl -pi -e 's|^description:.*|description: Delegate variant '"'"'creative'"'"' with model deepseek/deepseek-v4-pro. Use for creative writing, brainstorming, content generation, and open-ended exploration.|' "$AGENTS_DIR/delegate-creative.md"
    update_model "$AGENTS_DIR/delegate-creative.md" "deepseek/deepseek-v4-pro"
    if ! fm_grep "$AGENTS_DIR/delegate-creative.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-creative.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/delegate-creative.md"
    fi
fi
update_model "$AGENTS_DIR/doc-explorer.md"           "deepseek/deepseek-v4-pro"
# doc-explorer — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/doc-explorer.md" ]; then
    if ! fm_grep "$AGENTS_DIR/doc-explorer.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/doc-explorer.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/doc-explorer.md"
    fi
fi
update_model "$AGENTS_DIR/implementer.md"           "deepseek/deepseek-v4-pro"
# implementer — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/implementer.md" ]; then
    if ! fm_grep "$AGENTS_DIR/implementer.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/implementer.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/implementer.md"
    fi
fi
# implementer-safe — ensure reasoningEffort: xhigh
if [ -f "$AGENTS_DIR/implementer-safe.md" ]; then
    perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model:/) { $_ = "model: github-copilot/gpt-5.4-mini\n"; }' "$AGENTS_DIR/implementer-safe.md"
    if ! fm_grep "$AGENTS_DIR/implementer-safe.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: github-copilot/) { $_ .= "options:\n  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/implementer-safe.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: xhigh\n"; }' "$AGENTS_DIR/implementer-safe.md"
    fi
fi
update_model "$AGENTS_DIR/legacy-curator.md"        "deepseek/deepseek-v4-pro"
# legacy-curator — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/legacy-curator.md" ]; then
    if ! fm_grep "$AGENTS_DIR/legacy-curator.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/legacy-curator.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/legacy-curator.md"
    fi
fi
update_model "$AGENTS_DIR/lint.md"                   "deepseek/deepseek-v4-flash"
# lint — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/lint.md" ]; then
    if ! fm_grep "$AGENTS_DIR/lint.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/lint.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/lint.md"
    fi
fi
update_model "$AGENTS_DIR/learnings-researcher.md"   "deepseek/deepseek-v4-flash"
# learnings-researcher — ensure reasoningEffort: high
if [ -f "$AGENTS_DIR/learnings-researcher.md" ]; then
    if ! fm_grep "$AGENTS_DIR/learnings-researcher.md" "^options:"; then
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^model: deepseek/) { $_ .= "options:\n  reasoningEffort: high\n"; }' "$AGENTS_DIR/learnings-researcher.md"
    else
        perl -pi -e 'if (/^---/) { $fm++; } if ($fm < 2 && /^  reasoningEffort:/) { $_ = "  reasoningEffort: high\n"; }' "$AGENTS_DIR/learnings-researcher.md"
    fi
fi

# 6b. Warn about unhandled delegate-* agents
for f in "$AGENTS_DIR"/delegate-*.md; do
    [ -f "$f" ] || continue
    agent=$(basename "$f" .md)
    case "$agent" in
        delegate|delegate-fast|delegate-strong|delegate-gpt|delegate-opus|delegate-qwen|delegate-creative) ;;
        *) echo "NOTE: Unhandled agent $f — verify model manually" ;;
    esac
done

# 7. Set compaction and small model in opencode.json (pure jq, no python3)
if [ -f "$OPENCODE_JSON" ]; then
    if command -v jq >/dev/null 2>&1; then
        tmp_json="$(mktemp)"
        if jq '
          .small_model = "deepseek/deepseek-v4-flash" |
          .agent.compaction.model = "deepseek/deepseek-v4-flash"
        ' "$OPENCODE_JSON" > "$tmp_json"; then
            mv "$tmp_json" "$OPENCODE_JSON"
            echo "Compaction + small_model set to deepseek/deepseek-v4-flash (via jq)"
        else
            rm -f "$tmp_json"
            echo "ERROR: jq failed to update $OPENCODE_JSON" >&2
            exit 1
        fi
    else
        echo "WARNING: jq not found — skip setting compaction model"
        echo "Install jq or manually add compaction config to $OPENCODE_JSON"
    fi
fi

# 7b. Validate agent frontmatter after edits (perl5, no python3)
# Uses [-\w]+ to match hyphenated keys too.
perl -e '
use strict;
use warnings;
my $warned = 0;
for my $f (@ARGV) {
    open my $fh, "<", $f or next;
    my $text = do { local $/; <$fh> };
    close $fh;
    if ($text =~ /^---\n(.*?)\n---/s) {
        my $fm = $1;
        my %keys;
        while ($fm =~ /^([-\w]+):/mg) {
            if ($keys{$1}++) {
                print "WARNING: $f has duplicate key $1 in frontmatter\n";
                $warned++;
            }
        }
    } else {
        print "WARNING: $f missing frontmatter delimiters\n";
        $warned++;
    }
}
exit($warned > 0 ? 1 : 0);
' "$AGENTS_DIR"/*.md

echo ""
echo "=== Installation Complete ==="
echo "Models: @maintainer→deepseek/deepseek-v4-pro, delegate→deepseek/deepseek-v4-pro, strong→gpt-5.4, gpt→gpt-5.5, opus→claude-opus-4.8, qwen→deepseek/deepseek-v4-pro, creative→deepseek/deepseek-v4-pro, fast→deepseek/deepseek-v4-flash, implementer→deepseek/deepseek-v4-pro, implementer-safe→gpt-5.4-mini"
echo "OV5 Cowork: OpenCode configured"
echo "Backup: $BACKUP_DIR"
echo "Next: Restart OpenCode, select @maintainer agent"
