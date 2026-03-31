#!/usr/bin/env bash

# install-cron.sh
# Install cron jobs for autonomous operation (Cross-Platform)
#
# Usage:
#   ./scripts/install-cron.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be installed without modifying crontab
#
# Auto-detects machine and configures appropriate section in cron.d/auto-workflow
# Supports: macOS, Linux (Pi5/systemd), and generic single machine

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"

detect_machine() {
    local hostname=$(hostname -s 2>/dev/null || hostname)
    local os=$(uname -s)
    
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

MACHINE=$(detect_machine)
HOSTNAME=$(hostname -s 2>/dev/null || hostname)

echo "=== Installing Cron Jobs for Autonomous Operation ==="
echo ""
echo "Detected: $HOSTNAME ($MACHINE)"
echo ""

mkdir -p "$DIR/var/tmp/cron"
mkdir -p "$DIR/var/tmp/experiments"
echo "Created: var/tmp/cron/ var/tmp/experiments/"
echo ""

case "$MACHINE" in
    pi5|linux)
        PLATFORM="Linux"
        SCHEDULE="11PM, 3AM, 7AM, 11AM, 3PM, 7PM (6 runs/day)"
        DAEMON_CMD="systemctl --user start emacs"
        ;;
    macos)
        PLATFORM="macOS"
        SCHEDULE="10AM, 2PM, 6PM (3 runs/day) + weekly instincts"
        DAEMON_CMD="launchctl start emacs (or start Emacs.app)"
        ;;
    single)
        PLATFORM="Generic"
        SCHEDULE="Every 4 hours"
        DAEMON_CMD="emacs --daemon (or start Emacs GUI)"
        ;;
esac

if [ "$1" = "--dry-run" ]; then
    echo "DRY RUN - Would:"
    echo "  1. Comment out all job lines in all sections"
    echo "  2. Uncomment only $MACHINE section"
    echo "  3. Set platform-specific environment variables"
    echo ""
    echo "Active jobs would be:"
    grep "SECTION: $MACHINE" -A20 "$CRON_FILE" | grep "^#0 " | head -4 | sed 's/^#0/0/' || echo "  (no jobs found)"
    echo ""
    echo "To install for real, run:"
    echo "  ./scripts/install-cron.sh"
else
    TMP_FILE=$(mktemp)
    
    # Build crontab from scratch (skip original env lines to avoid duplicates)
    {
        # Header comment block (lines 1-19, before SHELL/PATH)
        sed -n '1,19p' "$CRON_FILE"
        
        # Environment variables (platform-specific, replaces original)
        echo "SHELL=/bin/bash"
        echo "PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:$HOME/.emacs.d/bin"
        if [ "$MACHINE" = "pi5" ] || [ "$MACHINE" = "linux" ]; then
            echo "XDG_RUNTIME_DIR=/run/user/1000"
        fi
        echo ""
        
        # Log directory creation
        echo "# Ensure log directory exists"
        echo "@reboot mkdir -p $HOME/.emacs.d/var/tmp/cron"
        echo ""
        
        # Process sections from line 30 (skip original env duplicate lines 20-29)
        awk -v machine="$MACHINE" '
            /^# .* SECTION: / {
                current_section = $NF
                in_selected = (current_section == machine)
            }
            /^#0 / {
                if (in_selected) {
                    print substr($0, 2)
                } else {
                    print
                }
                next
            }
            { print }
        ' "$CRON_FILE" | tail -n +30
    } > "$TMP_FILE"
    
    # Install crontab
    crontab "$TMP_FILE"
    rm -f "$TMP_FILE"
    
    echo "Installed crontab with $PLATFORM schedule"
    echo ""
    echo "Active jobs:"
    crontab -l | grep "^0 " || echo "  (no active jobs)"
    echo ""
    echo "Schedule: $SCHEDULE"
fi

echo ""
echo "=== Prerequisites ==="
echo ""
echo "1. Emacs daemon running: $DAEMON_CMD"
echo "2. Verify: emacsclient -e 't'"
echo "3. Check status: emacsclient -e '(gptel-auto-workflow-status)'"
echo "4. View logs: tail -f var/tmp/cron/*.log"
echo ""
echo "Done."
