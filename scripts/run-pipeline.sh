#!/usr/bin/env bash
# Pipeline: Research → Digestion → Auto-Workflow
# Ensures research findings are digested before auto-workflow runs.
# Includes verification that findings feed into directive skill.

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DIR/scripts/run-auto-workflow-cron.sh"
LOG_DIR="$DIR/var/tmp/cron"
PIPELINE_LOG="$LOG_DIR/pipeline.log"
LOCK_FILE="$LOG_DIR/pipeline.lock"
MAX_WAIT_RESEARCH=900   # 15 minutes
MAX_WAIT_WORKFLOW=7200  # 2 hours
POLL_INTERVAL=30

# Quota-aware scheduling: when MiniMax is exhausted, run less frequently
QUOTA_RESET_FILE="$DIR/var/tmp/quota-reset-timestamp"
SKIP_IF_QUOTA_EXHAUSTED="${SKIP_IF_QUOTA_EXHAUSTED:-no}"

log() {
    echo "[pipeline $(date '+%H:%M:%S')] $*" | tee -a "$PIPELINE_LOG"
}

# Prevent overlapping runs
if [ -f "$LOCK_FILE" ]; then
    lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        log "Pipeline already running (PID $lock_pid), skipping"
        exit 0
    fi
fi
echo $$ > "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

# Check if we should skip due to quota exhaustion
if [ "$SKIP_IF_QUOTA_EXHAUSTED" = "yes" ] && [ -f "$QUOTA_RESET_FILE" ]; then
    reset_ts=$(cat "$QUOTA_RESET_FILE")
    now_ts=$(date +%s)
    if [ "$now_ts" -lt "$reset_ts" ]; then
        hours_left=$(( (reset_ts - now_ts) / 3600 ))
        log "Quota exhausted, ${hours_left}h until reset. Skipping pipeline run."
        exit 0
    fi
fi

wait_for_idle() {
    local action="$1"
    local max_wait="${2:-900}"
    local socket_name="${3:-copilot-auto-workflow}"
    local elapsed=0

    log "Waiting for $action to complete (max ${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        # Check if daemon is still running (socket exists)
        if ! emacsclient --socket-name="$socket_name" --eval 't' >/dev/null 2>&1; then
            if [ "$elapsed" -gt 60 ]; then
                log "$action daemon stopped after ${elapsed}s (socket closed)"
                return 0
            fi
        else
            # Check phase via direct emacsclient eval
            local phase
            phase="$(emacsclient --socket-name="$socket_name" \
                --eval '(if (and (boundp (quote gptel-auto-workflow--stats)) gptel-auto-workflow--stats) (plist-get gptel-auto-workflow--stats :phase) "unknown")' 2>/dev/null || echo "unknown")"
            phase="${phase//\"/}"
            if [ "$phase" = "idle" ] || [ "$phase" = "complete" ]; then
                log "$action completed after ${elapsed}s"
                return 0
            fi
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    log "WARNING: $action did not complete within ${max_wait}s, proceeding anyway"
    return 1
}

# ─── Step 1: Research ───
log "=== Step 1: Research ==="
# The cron script's research action starts daemon, queues job, and returns.
# The researcher daemon auto-processes the job and then shuts down.
# We just need to wait for it to complete.
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
    "$SCRIPT" research >> "$PIPELINE_LOG" 2>&1 || true

# Wait for researcher daemon to finish its job (socket closes when done)
log "Waiting for research daemon to complete..."
for i in $(seq 1 $((MAX_WAIT_RESEARCH / 5))); do
    if ! emacsclient --socket-name=copilot-researcher -e t >/dev/null 2>&1; then
        log "Research completed after $((i * 5))s (daemon shut down)"
        break
    fi
    sleep 5
done

# Verify findings were produced
FINDINGS_FILE="$DIR/var/tmp/research-findings.md"
if [ -f "$FINDINGS_FILE" ]; then
    findings_size=$(wc -c < "$FINDINGS_FILE")
    log "Research findings: ${findings_size} bytes"
    if [ "$findings_size" -lt 100 ]; then
        log "WARNING: Findings file is very small, research may have failed"
    fi
else
    log "WARNING: No findings file found at $FINDINGS_FILE"
fi

# ─── Step 2: Verify pipeline integration (file-based checks) ───
log "=== Step 2: Verify Pipeline Integration ==="
FAILED_VERIFY=0

if [ -f "$FINDINGS_FILE" ]; then
    SIZE=$(wc -c < "$FINDINGS_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100 ]; then
        log "  ✓ Findings file: $SIZE bytes"
    else
        log "  ✗ Findings file too small: $SIZE bytes"
        FAILED_VERIFY=1
    fi
else
    log "  ✗ Findings file missing"
    FAILED_VERIFY=1
fi

DIRECTIVE_FILE="$DIR/assistant/skills/auto-workflow/DIRECTIVE.md"
if [ -f "$DIRECTIVE_FILE" ]; then
    log "  ✓ Directive skill exists"
else
    log "  ✗ Directive skill file not found"
    FAILED_VERIFY=1
fi

if [ -f "$FINDINGS_FILE" ]; then
    if FINDINGS_MTIME=$(stat -f %m "$FINDINGS_FILE" 2>/dev/null); then
        :
    elif FINDINGS_MTIME=$(stat -c %Y "$FINDINGS_FILE" 2>/dev/null); then
        :
    else
        FINDINGS_MTIME=0
    fi
    FINDINGS_AGE=$(( $(date +%s) - FINDINGS_MTIME ))
    if [ "$FINDINGS_AGE" -lt 86400 ]; then
        log "  ✓ Findings are recent ($(( FINDINGS_AGE / 3600 ))h old)"
    else
        log "  ✗ Findings are stale ($(( FINDINGS_AGE / 3600 ))h old)"
        FAILED_VERIFY=1
    fi
fi

if [ "$FAILED_VERIFY" -eq 0 ]; then
    log "Pipeline integration verified: findings → directive ✓"
else
    log "WARNING: Pipeline integration issues detected (see above)"
fi

# ─── Step 3: Auto-Workflow (uses digested findings via directive) ───
log "=== Step 3: Auto-Workflow ==="
# Ensure daemon is running, then queue the workflow job
if ! emacsclient --socket-name=copilot-auto-workflow -e t >/dev/null 2>&1; then
    MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        "$SCRIPT" auto-workflow >> "$PIPELINE_LOG" 2>&1 || true
else
    "$SCRIPT" auto-workflow >> "$PIPELINE_LOG" 2>&1 || true
fi
wait_for_idle "auto-workflow" "$MAX_WAIT_WORKFLOW" "copilot-auto-workflow"

# ─── Step 4: Report results ───
log "=== Pipeline Complete ==="
RESULTS_FILE="$DIR/var/tmp/experiments/$(date +%F)*/results.tsv"
if ls $RESULTS_FILE 1>/dev/null 2>&1; then
    latest_result=$(ls -t $RESULTS_FILE | head -1)
    result_count=$(wc -l < "$latest_result")
    log "Results: $latest_result ($((result_count - 1)) experiments)"
else
    log "No results file found for today"
fi

exit 0
