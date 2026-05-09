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
    local elapsed=0

    log "Waiting for $action to complete (max ${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        local phase
        phase="$($SCRIPT status 2>/dev/null | sed -n 's/.*:phase "\([^"]*\)".*/\1/p' || echo "unknown")"

        if [ "$phase" = "idle" ] || [ "$phase" = "complete" ]; then
            log "$action completed after ${elapsed}s"
            return 0
        fi

        sleep "$POLL_INTERVAL"
        elapsed=$((elapsed + POLL_INTERVAL))
    done

    log "WARNING: $action did not complete within ${max_wait}s, proceeding anyway"
    return 1
}

# ─── Step 1: Research ───
log "=== Step 1: Research ==="
"$SCRIPT" research >> "$PIPELINE_LOG" 2>&1 || true
wait_for_idle "research" "$MAX_WAIT_RESEARCH"

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

# ─── Step 2: Verify pipeline integration (Elisp check) ───
log "=== Step 2: Verify Pipeline Integration ==="
verify_output=$(emacsclient --socket-name=copilot-auto-workflow \
    --eval '(when (fboundp (quote gptel-auto-workflow--verify-pipeline-integration)) (gptel-auto-workflow--verify-pipeline-integration))' 2>&1 || echo "daemon-unavailable")

if echo "$verify_output" | grep -q "daemon-unavailable"; then
    log "WARNING: Could not connect to daemon for verification"
elif echo "$verify_output" | grep -q "✓ All checks passed"; then
    log "Pipeline integration verified: findings → directive ✓"
else
    log "Pipeline integration issues detected (see elisp output)"
    log "Elisp output: $verify_output"
fi

# ─── Step 3: Auto-Workflow (uses digested findings via directive) ───
log "=== Step 3: Auto-Workflow ==="
"$SCRIPT" auto-workflow >> "$PIPELINE_LOG" 2>&1 || true
wait_for_idle "auto-workflow" "$MAX_WAIT_WORKFLOW"

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