#!/usr/bin/env bash

# install-cron.sh
# Install cron jobs for autonomous operation
#
# Usage:
#   ./scripts/install-cron.sh [--dry-run]
#
# Options:
#   --dry-run    Show what would be installed without modifying crontab
#
# Auto-detects machine and uncomment appropriate section in cron.d/auto-workflow

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"

detect_machine() {
    local hostname=$(hostname)
    local os=$(uname -s)
    
    if [ "$os" = "Darwin" ]; then
        echo "macos"
    elif echo "$hostname" | grep -qiE "pi5|raspberrypi|onepi"; then
        echo "pi5"
    else
        echo "single"
    fi
}

MACHINE=$(detect_machine)
HOSTNAME=$(hostname)

echo "=== Installing Cron Jobs for Autonomous Operation ==="
echo ""
echo "Detected: $HOSTNAME ($MACHINE)"
echo ""

mkdir -p "$DIR/var/tmp/cron"
mkdir -p "$DIR/var/tmp/experiments"
echo "Created: var/tmp/cron/ var/tmp/experiments/"
echo ""

case "$MACHINE" in
    pi5)
        SECTION_START=34
        SECTION_END=37
        SOCKET="-s /run/user/1000/emacs/server"
        SCHEDULE="11PM, 3AM, 7AM, 11AM, 3PM, 7PM (6 runs/day)"
        ;;
    macos)
        SECTION_START=48
        SECTION_END=51
        SOCKET=""
        SCHEDULE="10AM, 2PM, 6PM (3 runs/day)"
        ;;
    single)
        SECTION_START=59
        SECTION_END=62
        SOCKET=""
        SCHEDULE="Every 4 hours"
        ;;
esac

if [ "$1" = "--dry-run" ]; then
    echo "DRY RUN - Would:"
    echo "  1. Comment out all job lines"
    echo "  2. Uncomment lines $SECTION_START-$SECTION_END for $MACHINE"
    echo ""
    sed -n "${SECTION_START},${SECTION_END}p" "$CRON_FILE" | sed 's/^#0/0/'
    echo ""
    echo "To install for real, run:"
    echo "  ./scripts/install-cron.sh"
else
    TMP_FILE=$(mktemp)
    # First comment out ALL job lines (0 at start of line), then uncomment selected section
    sed -e 's/^0 /#0 /' -e "${SECTION_START},${SECTION_END}s/^#0/0/" "$CRON_FILE" > "$TMP_FILE"
    crontab "$TMP_FILE"
    rm "$TMP_FILE"
    echo "Installed crontab with $MACHINE schedule"
    echo ""
    echo "Active jobs:"
    crontab -l | grep "^0"
    echo ""
    echo "Socket: ${SOCKET:-default}"
    echo "Schedule: $SCHEDULE"
fi

echo ""
echo "=== Prerequisites ==="
echo ""
echo "1. Emacs daemon running: systemctl --user start emacs"
echo "2. Verify: emacsclient -e 't'"
echo "3. Check status: emacsclient -e '(gptel-auto-workflow-status)'"
echo "4. View logs: tail -f var/tmp/cron/*.log"
echo ""
echo "Done."