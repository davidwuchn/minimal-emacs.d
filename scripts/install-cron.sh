#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"
MODE="${1:-install}"
MANAGED_BLOCK_BEGIN="# >>> minimal-emacs.d auto-workflow >>>"
MANAGED_BLOCK_END="# <<< minimal-emacs.d auto-workflow <<<"

detect_machine() {
    local hostname os
    hostname=$(hostname -s 2>/dev/null || hostname)
    os=$(uname -s)

    if [ "$os" = "Darwin" ]; then
        echo "macos"
    elif echo "$hostname" | grep -qiE "pi5|raspberrypi|onepi"; then
        echo "pi5"
    elif [ "$os" = "Linux" ]; then
        echo "linux"
    else
        echo "single"
    fi
}

render_crontab() {
    local machine="$1"
    {
        # Header: all comment lines before the first SHELL= line
        awk '/^SHELL=/{exit} {print}' "$CRON_FILE"
        echo "SHELL=/bin/bash"
        if [ "$machine" = "macos" ]; then
            echo "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:$HOME/.emacs.d/bin"
        else
            echo "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:$HOME/.emacs.d/bin"
        fi
        if [ "$machine" = "pi5" ] || [ "$machine" = "linux" ]; then
            echo "XDG_RUNTIME_DIR=/run/user/$(id -u)"
        fi
        echo
        echo "# Ensure log directory exists"
        echo "@reboot mkdir -p $HOME/.emacs.d/var/tmp/cron"
        echo
        # Sections: start from first '---' separator; strip env vars already emitted above
        awk -v machine="$machine" '
            /^# -{5,}/ { found=1 }
            !found { next }
            /^# .* SECTION: / {
                current_section = $NF
                in_selected = (current_section == machine)
                print
                next
            }
            /^#0 / {
                if (in_selected) {
                    print substr($0, 2)
                } else {
                    print
                }
                next
            }
            /^SHELL=/ || /^PATH=/ || /^XDG_RUNTIME_DIR=/ || /^@reboot mkdir/ { next }
            { print }
        ' "$CRON_FILE"
    }
}

render_managed_crontab() {
    echo "$MANAGED_BLOCK_BEGIN"
    render_crontab "$1"
    echo "$MANAGED_BLOCK_END"
}

merge_crontab() {
    local rendered_file="$1"
    local output_file="$2"
    local existing_file

    existing_file=$(mktemp)
    if crontab -l > "$existing_file" 2>/dev/null; then
        python3 - "$existing_file" "$rendered_file" "$output_file" \
                 "$MANAGED_BLOCK_BEGIN" "$MANAGED_BLOCK_END" <<'PY'
from pathlib import Path
import re
import sys

existing_path, rendered_path, output_path, begin_marker, end_marker = sys.argv[1:]
existing = Path(existing_path).read_text(encoding="utf-8")
rendered = Path(rendered_path).read_text(encoding="utf-8").rstrip() + "\n"

# Strip markers from rendered content to detect duplicate raw blocks
rendered_raw = rendered.replace(begin_marker + "\n", "").replace(end_marker + "\n", "")

managed_pattern = re.compile(
    rf"(?ms)^[ \t]*{re.escape(begin_marker)}\n.*?^[ \t]*{re.escape(end_marker)}\n?"
)

# First: remove any duplicate raw content (without markers) that matches rendered content
# This handles legacy installs that added content before the managed block system
lines = existing.split("\n")
cleaned_lines = []
skip_until_next_section = False
in_raw_block = False
raw_block_lines = []

for i, line in enumerate(lines):
    if line.strip() == begin_marker.strip():
        # Skip everything inside managed block (will be replaced below)
        in_raw_block = False
        skip_until_next_section = True
        continue
    if skip_until_next_section:
        if line.strip() == end_marker.strip():
            skip_until_next_section = False
        continue

    # Detect raw cron blocks that match rendered content
    # A raw block starts with a comment header and ends with cron jobs
    if line.startswith("# Auto-Workflow") or line.startswith("# -" * 10):
        # Check if this looks like a duplicate of our rendered content
        # by looking for characteristic patterns
        block_start = i
        block_lines = [line]
        j = i + 1
        while j < len(lines):
            block_lines.append(lines[j])
            # Stop at next major section or end of file
            if lines[j].startswith("# ---") and j > block_start + 3:
                break
            if lines[j].startswith("# >>>") or lines[j].startswith("# <<<"):
                break
            j += 1

        block_text = "\n".join(block_lines) + "\n"
        # Check if this block contains the same cron jobs as rendered content
        # by looking for active (uncommented) cron lines
        active_cron_re = re.compile(r"^\d")
        rendered_active = [l for l in rendered_raw.split("\n") if active_cron_re.match(l)]
        block_active = [l for l in block_text.split("\n") if active_cron_re.match(l)]

        if rendered_active and block_active and set(rendered_active) == set(block_active):
            # This is a duplicate raw block - skip it
            i = j
            continue
        else:
            cleaned_lines.append(line)
    else:
        cleaned_lines.append(line)

existing = "\n".join(cleaned_lines)

# Now handle the managed block
if managed_pattern.search(existing):
    merged = managed_pattern.sub(rendered, existing, count=1)
else:
    merged = existing.rstrip()
    if merged:
        merged += "\n\n"
    merged += rendered

if not merged.endswith("\n"):
    merged += "\n"

Path(output_path).write_text(merged, encoding="utf-8")
PY
    else
        cp "$rendered_file" "$output_file"
    fi
    rm -f "$existing_file"
}

MACHINE=$(detect_machine)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

case "$MACHINE" in
    pi5|linux)
        PLATFORM="Linux"
        SCHEDULE="11PM, 3AM, 7AM, 11AM, 3PM, 7PM (6 runs/day)"
        DAEMON_CMD="systemctl --user start emacs"
        MACHINE_RENDER="pi5"
        ;;
    macos)
        PLATFORM="macOS"
        SCHEDULE="10AM, 2PM, 6PM (3 runs/day) + weekly instincts"
        DAEMON_CMD="launchctl start emacs (or start Emacs.app)"
        MACHINE_RENDER="macos"
        ;;
    single)
        PLATFORM="Generic"
        SCHEDULE="Every 4 hours"
        DAEMON_CMD="emacs --daemon (or start Emacs GUI)"
        MACHINE_RENDER="single"
        ;;
esac

case "$MODE" in
    --render)
        render_managed_crontab "$MACHINE_RENDER"
        exit 0
        ;;
    --dry-run)
        echo "=== Installing Cron Jobs for Autonomous Operation ==="
        echo
        echo "Detected: $HOSTNAME ($MACHINE)"
        echo
        echo "DRY RUN - Rendered crontab:"
        render_managed_crontab "$MACHINE_RENDER"
        exit 0
        ;;
    install)
        mkdir -p "$DIR/var/tmp/cron" "$DIR/var/tmp/experiments"
        echo "=== Installing Cron Jobs for Autonomous Operation ==="
        echo
        echo "Detected: $HOSTNAME ($MACHINE)"
        echo
        tmp_file=$(mktemp)
        rendered_file=$(mktemp)
        trap 'rm -f "$tmp_file" "$rendered_file"' EXIT
        render_managed_crontab "$MACHINE_RENDER" > "$rendered_file"
        merge_crontab "$rendered_file" "$tmp_file"
        crontab "$tmp_file"
        rm -f "$tmp_file" "$rendered_file"
        echo "Installed auto-workflow cron block with $PLATFORM schedule"
        echo
        echo "Active jobs:"
        crontab -l | grep -E '^[0-9*@]' || echo "  (no active jobs)"
        echo
        echo "Schedule: $SCHEDULE"
        echo
        echo "=== Prerequisites ==="
        echo
        echo "1. No manual cron daemon setup is required; the wrapper starts a dedicated auto-workflow daemon on demand."
        echo "2. Smoke test a real run: ./scripts/run-auto-workflow-cron.sh auto-workflow"
        echo "3. Confirm progress/results: ./scripts/run-auto-workflow-cron.sh status && ./scripts/run-auto-workflow-cron.sh messages"
        echo "4. Check logs: tail -f var/tmp/cron/*.log"
        echo
        echo "Done."
        exit 0
        ;;
    *)
        echo "Usage: $0 [install|--dry-run|--render]" >&2
        exit 2
        ;;
esac
