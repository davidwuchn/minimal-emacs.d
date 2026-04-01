#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CRON_FILE="$DIR/cron.d/auto-workflow"
MODE="${1:-install}"

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
        sed -n '1,19p' "$CRON_FILE"
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
        awk -v machine="$machine" '
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
        ' "$CRON_FILE" | sed -n '30,$p'
    }
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

if [ "$MACHINE" = "linux" ] || [ "$MACHINE" = "pi5" ]; then
    MACHINE_RENDER="pi5"
fi

mkdir -p "$DIR/var/tmp/cron" "$DIR/var/tmp/experiments"

case "$MODE" in
    --render)
        render_crontab "$MACHINE_RENDER"
        exit 0
        ;;
    --dry-run)
        echo "=== Installing Cron Jobs for Autonomous Operation ==="
        echo
        echo "Detected: $HOSTNAME ($MACHINE)"
        echo
        echo "DRY RUN - Rendered crontab:"
        render_crontab "$MACHINE_RENDER"
        exit 0
        ;;
    install)
        echo "=== Installing Cron Jobs for Autonomous Operation ==="
        echo
        echo "Detected: $HOSTNAME ($MACHINE)"
        echo
        tmp_file=$(mktemp)
        render_crontab "$MACHINE_RENDER" > "$tmp_file"
        crontab "$tmp_file"
        rm -f "$tmp_file"
        echo "Installed crontab with $PLATFORM schedule"
        echo
        echo "Active jobs:"
        crontab -l | grep -E '^[0-9*@]' || echo "  (no active jobs)"
        echo
        echo "Schedule: $SCHEDULE"
        echo
        echo "=== Prerequisites ==="
        echo
        echo "1. Emacs daemon running: $DAEMON_CMD"
        echo "2. Verify: ./scripts/run-auto-workflow-cron.sh status"
        echo "3. Check logs: tail -f var/tmp/cron/*.log"
        echo
        echo "Done."
        exit 0
        ;;
    *)
        echo "Usage: $0 [--dry-run|--render]" >&2
        exit 2
        ;;
esac
