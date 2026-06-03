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
        # Check for Raspberry Pi hardware (Pi5, Pi4, etc.)
        if [ -f /proc/device-tree/model ] && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
            echo "pi5"
        # Check for ARM Linux with limited RAM (typical Pi)
        elif [ "$(uname -m)" = "aarch64" ] && [ "$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)" -lt 8192 ]; then
            echo "pi5"
        else
            echo "linux"
        fi
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
            echo "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:\$HOME/.emacs.d/bin:\$HOME/.venv/bin"
        else
            echo "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:\$HOME/.emacs.d/bin:\$HOME/.venv/bin"
        fi
        if [ "$machine" = "pi5" ] || [ "$machine" = "linux" ]; then
            echo "XDG_RUNTIME_DIR=/run/user/$(id -u)"
        fi
        echo "MAILTO=\"\""
        echo
        echo "# Watchdog: restart daemon if unresponsive (every 30min, reaper handles 95%)"
        echo "*/30 * * * * \$HOME/.emacs.d/scripts/watchdog-daemon.sh"
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

    # If there's no existing crontab, use rendered directly
    if ! crontab -l > /dev/null 2>&1; then
        cp "$rendered_file" "$output_file"
        return
    fi

    local existing_file
    existing_file=$(mktemp)
    crontab -l > "$existing_file" 2>/dev/null || true
    python3 - "$existing_file" "$rendered_file" "$output_file" \
             "$MANAGED_BLOCK_BEGIN" "$MANAGED_BLOCK_END" <<'PY'
from pathlib import Path
import re
import sys

existing_path, rendered_path, output_path, begin_marker, end_marker = sys.argv[1:]
existing = Path(existing_path).read_text(encoding="utf-8")
rendered = Path(rendered_path).read_text(encoding="utf-8").rstrip() + "\n"

managed_pattern = re.compile(
    rf"(?ms)^[ \t]*{re.escape(begin_marker)}\n.*?^[ \t]*{re.escape(end_marker)}\n?"
)

# If a managed block already exists, replace it with rendered content
if managed_pattern.search(existing):
    merged = managed_pattern.sub(rendered, existing, count=1)
else:
    # No managed block: cleanup old cron lines from previous installs
    # that use the same scripts (run-pipeline.sh or run-auto-workflow-cron.sh)
    cleaned_lines = []
    active_cron_re = re.compile(r"^\s*(?:\d+[,\d*\-\/]+\s+)+")
    for line in existing.split("\n"):
        stripped = line.strip()
        # Skip empty lines and comments
        if not stripped or stripped.startswith("#"):
            cleaned_lines.append(line)
            continue
        # Check if this is an active cron line using our scripts
        if active_cron_re.match(stripped) and (
            "run-pipeline.sh" in stripped or
            "run-auto-workflow-cron.sh" in stripped or
            "watchdog-daemon.sh" in stripped
        ):
            continue  # Skip old lines — will be replaced by rendered
        cleaned_lines.append(line)

    existing = "\n".join(cleaned_lines).strip()
    if existing:
        merged = existing + "\n\n" + rendered
    else:
        merged = rendered

if not merged.endswith("\n"):
    merged += "\n"

Path(output_path).write_text(merged, encoding="utf-8")
PY
    rm -f "$existing_file"
}

MACHINE=$(detect_machine)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

case "$MACHINE" in
    pi5|linux)
        PLATFORM="Linux"
        SCHEDULE="11PM, 3AM, 7AM, 11AM, 3PM, 7PM (6 pipeline runs/day)"
        DAEMON_CMD="systemctl --user start emacs"
        MACHINE_RENDER="pi5"
        ;;
    macos)
        PLATFORM="macOS"
        SCHEDULE="10AM, 2PM, 6PM (3 pipeline runs/day) + daily mementum/instincts at 2AM/3AM"
        DAEMON_CMD="launchctl start emacs (or start Emacs.app)"
        MACHINE_RENDER="macos"
        ;;
    single)
        PLATFORM="Generic"
        SCHEDULE="Every 4 hours (6 pipeline runs/day) + daily mementum/instincts at 2AM/3AM"
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
        # Verify python3 is available (required for merge logic)
        if ! command -v python3 &>/dev/null; then
            echo "ERROR: python3 is required but not found." >&2
            echo "Install it: sudo apt-get install python3" >&2
            exit 1
        fi

        # Verify pipeline script exists and is executable
        PIPELINE_SCRIPT="$DIR/scripts/run-pipeline.sh"
        if [ ! -x "$PIPELINE_SCRIPT" ]; then
            echo "ERROR: Pipeline script not found or not executable: $PIPELINE_SCRIPT" >&2
            echo "Run: chmod +x scripts/run-pipeline.sh" >&2
            exit 1
        fi

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

        # Verify pipeline job was installed
        if ! crontab -l | grep -q "run-pipeline.sh"; then
            echo "WARNING: Pipeline cron job not found in installed crontab" >&2
            echo "Check: crontab -l | grep pipeline" >&2
        fi

        echo "Installed auto-workflow cron block with $PLATFORM schedule"
        echo
        echo "=== Installing Emacs dependencies ==="
        echo
        # Install yaml ELPA package (required for parsing agent .md files with block scalars)
        if command -v emacs &>/dev/null; then
            install_log=$(mktemp)
            emacs --batch \
                --eval "(setq package-user-dir (expand-file-name \"var/elpa\" \"$DIR\"))" \
                --eval "(require 'package)" \
                --eval "(add-to-list 'package-archives '(\"melpa\" . \"https://melpa.org/packages/\") t)" \
                --eval "(package-initialize)" \
                --eval "(unless (package-installed-p 'yaml) (package-refresh-contents) (package-install 'yaml))" \
                --eval "(when (package-installed-p 'yaml) (message \"yaml installed\") (kill-emacs 0)) (message \"yaml not installed\") (kill-emacs 1)" \
                > /dev/null 2>&1 && echo "  ✓ yaml ELPA package installed" \
                || echo "  ⚠ yaml package install skipped (will use built-in YAML parser)"
            rm -f "$install_log"
        else
            echo "  ⚠ emacs not found — yaml ELPA package not installed (agent loading may be limited)"
        fi
        echo
        echo "Active jobs:"
        crontab -l | grep -E '^[0-9*@]' || echo "  (no active jobs)"
        echo
        echo "Schedule: $SCHEDULE"
        echo
        echo "=== Pipeline Architecture ==="
        echo
        echo "Each scheduled run executes the full pipeline:"
        echo "  1. Research   → Hunts external ideas + local pattern analysis"
        echo "  2. Digestion  → LLM distills findings into actionable hypotheses"
        echo "  3. Verify     → Checks findings feed into directive skill"
        echo "  4. Auto-work  → Runs experiments using directive hypotheses"
        echo "  5. Evolution  → Self-evolves skills internally (1h timer)"
        echo
        echo "=== Quick Start ==="
        echo
        echo "1. Smoke test pipeline:     ./scripts/run-pipeline.sh"
        echo "2. Check daemon status:     ./scripts/run-auto-workflow-cron.sh status"
        echo "3. View pipeline logs:      tail -f var/tmp/cron/pipeline.log"
        echo "4. View experiment logs:    tail -f var/tmp/cron/ov5-auto-workflow.log"
        echo "5. Quota-aware skip:        SKIP_IF_QUOTA_EXHAUSTED=yes ./scripts/run-pipeline.sh"
        echo
        echo "Done."
        exit 0
        ;;
     uninstall)
        echo "=== Uninstalling Auto-Workflow Cron Jobs ==="
        echo
        echo "Detected: $HOSTNAME ($MACHINE)"
        echo
        if ! crontab -l >/dev/null 2>&1; then
            echo "No crontab found. Nothing to uninstall."
            exit 0
        fi
        cleaned=$(mktemp)
        trap 'rm -f "$cleaned"' EXIT
        crontab -l | python3 - "$cleaned" "$MANAGED_BLOCK_BEGIN" "$MANAGED_BLOCK_END" <<'PY'
from pathlib import Path
import re
import sys

output_path, begin_marker, end_marker = sys.argv[1:]
text = sys.stdin.read()

managed_pattern = re.compile(
    rf"(?m)^[ \t]*{re.escape(begin_marker)}\n.*?^[ \t]*{re.escape(end_marker)}\n?"
)

cleaned = managed_pattern.sub("", text, count=1)
# Collapse multiple blank lines left by removal
cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
cleaned = cleaned.strip() + "\n" if cleaned.strip() else ""

Path(output_path).write_text(cleaned, encoding="utf-8")
PY
        if [ -s "$cleaned" ]; then
            crontab "$cleaned"
            echo "Auto-workflow cron block removed."
        else
            crontab -r
            echo "Auto-workflow cron block removed (crontab now empty)."
        fi
        echo
        echo "Note: Log files in var/tmp/cron/ were not removed."
        echo "  To clean up: rm -rf var/tmp/cron/"
        exit 0
        ;;
    *)
        echo "Usage: $0 [install|--dry-run|--render|uninstall]" >&2
        exit 2
        ;;
esac
