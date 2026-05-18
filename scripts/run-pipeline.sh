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
MAX_WAIT_RESEARCH="${MAX_WAIT_RESEARCH:-900}"   # 15 minutes
MAX_WAIT_EVOLUTION="${MAX_WAIT_EVOLUTION:-900}" # 15 minutes
MAX_WAIT_WORKFLOW="${MAX_WAIT_WORKFLOW:-14400}" # 4 hours
POLL_INTERVAL="${POLL_INTERVAL:-30}"
PIPELINE_SMOKE_ONLY="${PIPELINE_SMOKE_ONLY:-no}"

# Quota-aware scheduling: when MiniMax is exhausted, run less frequently
QUOTA_RESET_FILE="$DIR/var/tmp/quota-reset-timestamp"

# Research output files
FINDINGS_FILE="$DIR/var/tmp/research-findings.md"
INTERNAL_FILE="$DIR/var/tmp/internal-research.md"
SKIP_IF_QUOTA_EXHAUSTED="${SKIP_IF_QUOTA_EXHAUSTED:-no}"

mkdir -p "$LOG_DIR"

log() {
    local line stdout_path log_path

    line="[pipeline $(date '+%H:%M:%S')] $*"
    stdout_path="$(readlink -f /proc/$$/fd/1 2>/dev/null || true)"
    log_path="$(readlink -f "$PIPELINE_LOG" 2>/dev/null || true)"

    if [ -n "$stdout_path" ] && [ -n "$log_path" ] && [ "$stdout_path" = "$log_path" ]; then
        printf '%s\n' "$line"
    else
        printf '%s\n' "$line" | tee -a "$PIPELINE_LOG"
    fi
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
    local daemon_was_seen=0
    local min_start_wait="${4:-60}"

    log "Waiting for $action to complete (max ${max_wait}s)..."
    while [ "$elapsed" -lt "$max_wait" ]; do
        if [ "$socket_name" = "copilot-auto-workflow" ]; then
            local status
            status="$($SCRIPT status 2>/dev/null || true)"
            if printf '%s' "$status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"|:running nil'; then
                log "$action completed after ${elapsed}s"
                return 0
            fi
            daemon_was_seen=1
        elif [ "$socket_name" = "copilot-researcher" ]; then
            # Researcher daemon is persistent; wait for findings file instead
            if [ -f "$FINDINGS_FILE" ] && [ "$(wc -c < "$FINDINGS_FILE" 2>/dev/null || echo 0)" -gt 100 ]; then
                if findings_mtime="$(stat -f %m "$FINDINGS_FILE" 2>/dev/null)"; then
                    :
                elif findings_mtime="$(stat -c %Y "$FINDINGS_FILE" 2>/dev/null)"; then
                    :
                else
                    findings_mtime=0
                fi
                if [ "$findings_mtime" -ge "$PIPELINE_START_TIME" ]; then
                    log "$action completed after ${elapsed}s (findings file ready)"
                    return 0
                fi
            fi
            # Actually check if researcher daemon is alive
            if emacsclient --socket-name="copilot-researcher" --eval 't' >/dev/null 2>&1; then
                daemon_was_seen=1
            elif [ "$daemon_was_seen" -eq 1 ]; then
                log "WARNING: $action daemon stopped after ${elapsed}s without findings"
                return 1
            fi
            if [ "$elapsed" -ge "$min_start_wait" ] && [ "$daemon_was_seen" -eq 0 ]; then
                log "WARNING: $action daemon was not observed within ${elapsed}s"
                return 1
            fi
        elif ! emacsclient --socket-name="$socket_name" --eval 't' >/dev/null 2>&1; then
            if [ "$daemon_was_seen" -eq 1 ]; then
                log "$action daemon stopped after ${elapsed}s (socket closed)"
                return 0
            fi
            if [ "$elapsed" -ge "$min_start_wait" ]; then
                log "WARNING: $action daemon was not observed within ${elapsed}s"
                return 1
            fi
        else
            daemon_was_seen=1
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

    log "WARNING: $action did not complete within ${max_wait}s"
    return 1
}

run_self_evolution() {
    local label="$1"
    local evolution_output

    log "=== $label ==="

    evolution_output="$(AUTO_WORKFLOW_ACTION_TIMEOUT="$MAX_WAIT_EVOLUTION" \
        MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
        "$SCRIPT" evolution 2>&1)"
    printf '%s\n' "$evolution_output" >> "$PIPELINE_LOG"
    if printf '%s' "$evolution_output" | grep -q "already-running"; then
        log "Self-evolution skipped (already running)"
    elif printf '%s' "$evolution_output" | grep -q "Insufficient new data"; then
        log "Self-evolution skipped (insufficient new data)"
    elif printf '%s' "$evolution_output" | grep -q "Self-evolution cycle complete"; then
        log "Self-evolution completed (research: $RESEARCH_QUALITY)"
    else
        log "WARNING: self-evolution command had issues, but continuing pipeline"
        # Non-fatal: evolution failure shouldn't stop experiments
    fi
}

write_research_fallback() {
    local reason="$1"

    mkdir -p "$(dirname "$FINDINGS_FILE")"
    cat > "$FINDINGS_FILE" <<EOF
# Research Findings

> Updated: $(date '+%Y-%m-%d %H:%M')
> Source type: local-fallback
> Reason: $reason

## Local Research Fallback

The dedicated researcher daemon did not produce fresh external findings. Use this local context rather than running auto-workflow with no research signal:

- Preserve the feedback loop: every experiment row must include a non-none research hash so AutoTTS can link outcomes back to the research trace.
- Treat missing research files as a pipeline defect, not a successful empty research run.
- Prefer structured, machine-parseable research outputs with source, technique, apply-to-us, and verification fields.
- Guard daemon orchestration boundaries: if a researcher daemon disappears after being observed, fail fast and fall back instead of waiting until the global timeout.
- Prioritize changes that make self-evolution observable through results.tsv metadata, research traces, and controller decisions.

EOF
    cat > "$INTERNAL_FILE" <<EOF
# Internal Code Analysis

> Updated: $(date '+%Y-%m-%d %H:%M')
> Source type: local-fallback

The pipeline generated fallback research because the researcher daemon did not produce fresh findings. This is still useful input for self-evolution: focus on daemon lifecycle, result metadata, trace outcome linking, and pipeline validation.

EOF
    if [ "$RESEARCH_QUALITY" = "none" ] || [ "$RESEARCH_QUALITY" = "failed" ]; then
        RESEARCH_QUALITY="internal"
    fi
    log "Generated local research fallback after: $reason"
}

verify_research_feedback_loop() {
    local results_file="$1"
    local data_rows linked_rows

    if [ "$RESEARCH_QUALITY" != "external" ]; then
        return 0
    fi
    if [ ! -f "$results_file" ]; then
        return 0
    fi

    data_rows=$(awk 'NR > 1 { count++ } END { print count + 0 }' "$results_file")
    if [ "$data_rows" -eq 0 ]; then
        log "WARNING: No experiment rows found to validate research feedback loop"
        return 0
    fi

    linked_rows=$(awk 'BEGIN { FS = sprintf("%c", 9) } NR > 1 && $22 != "" && $22 != "none" { count++ } END { print count + 0 }' "$results_file")
    if [ "$linked_rows" -eq 0 ]; then
        log "WARNING: Research feedback loop broken: 0/${data_rows} experiment rows have a research hash"
        return 1
    fi

    log "Research feedback loop: ${linked_rows}/${data_rows} experiment rows linked to research"
}

# ─── Clear stale byte-compiled files to force source reload ───
find "$DIR/lisp/modules" -name "*.elc" -delete 2>/dev/null || true
log "Cleared stale .elc files from lisp/modules/"

# ─── Force-kill all stale Emacs daemons ───
STALE_COUNT=$(ps aux | grep -c "[e]macs.*aw-complete\|[e]macs.*bg-daemon" 2>/dev/null || echo 0)
if [ "$STALE_COUNT" -gt 0 ]; then
    log "Killing $STALE_COUNT stale experiment daemons..."
    ps aux | grep "[e]macs.*aw-complete\|[e]macs.*bg-daemon" | awk '{print $2}' | xargs kill -9 2>/dev/null || true
    sleep 2
fi
# Clean default server socket (blocks --daemon startup)
if [ -S /var/folders/*/*/*/emacs*/server ]; then
    rm -f /var/folders/*/*/*/emacs*/server 2>/dev/null || true
    log "Cleared stale default server socket"
fi

# ─── Stop any existing daemons to ensure fresh code is loaded ───
log "Stopping any existing daemons to load latest code..."
"$SCRIPT" stop >/dev/null 2>&1 || true
AUTO_WORKFLOW_EMACS_SERVER=copilot-researcher "$SCRIPT" stop >/dev/null 2>&1 || true
sleep 2

# ─── Clear stale findings to ensure fresh research ───
rm -f "$FINDINGS_FILE" "$INTERNAL_FILE"
log "Cleared stale findings files"

# Capture start time AFTER clearing stale files so mtime check is reliable
PIPELINE_START_TIME="$(date +%s)"

# Verify findings were produced
RESEARCH_QUALITY="none"

# ─── Step 0: Pre-fetch external repo content (optional — researcher can fetch on demand) ───
PREFETCH_FILE="$DIR/var/tmp/prefetched-research.md"
PREFETCH_SCRIPT="$DIR/scripts/prefetch-research-repos.sh"
PREFETCH_ENABLED="${PREFETCH_ENABLED:-no}"  # off by default — researcher fetches what it needs
if [ "$PREFETCH_ENABLED" = "yes" ] && [ -x "$PREFETCH_SCRIPT" ] && command -v gh >/dev/null 2>&1; then
    log "=== Step 0: Pre-fetch Research Repos (broad batch) ==="
    if "$PREFETCH_SCRIPT" "$PREFETCH_FILE" >> "$PIPELINE_LOG" 2>&1; then
        log "  ✓ Pre-fetched repo content ($(wc -c < "$PREFETCH_FILE" 2>/dev/null || echo 0)B)"
        export PIPELINE_PREFETCH_FILE="$PREFETCH_FILE"
    else
        log "  ⚠ Pre-fetch had issues — researcher will fetch on demand"
        rm -f "$PREFETCH_FILE"
    fi
else
    log "=== Step 0: Skipped (researcher fetches specific files on demand) ==="
fi

# ─── Step 1: Research ───
log "=== Step 1: Research ==="
# The cron script's research action starts daemon, queues job, and returns.
# The researcher daemon auto-processes the job and then shuts down.
# We just need to wait for it to complete.
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
    "$SCRIPT" research >> "$PIPELINE_LOG" 2>&1 || true
# Researcher daemon startup can take 90-120s (emacs init + package loading).
# Use min_start_wait=120 to give it enough time before giving up.
if ! wait_for_idle "research" "$MAX_WAIT_RESEARCH" "copilot-researcher" 120; then
    AUTO_WORKFLOW_EMACS_SERVER=copilot-researcher "$SCRIPT" stop >> "$PIPELINE_LOG" 2>&1 || true
    write_research_fallback "research daemon ended before producing findings"
fi

if [ -f "$FINDINGS_FILE" ]; then
    findings_size=$(wc -c < "$FINDINGS_FILE")
    log "Research findings: ${findings_size} bytes"
    
    # If findings are local fallback AND we have pre-fetched content, use that instead
    if (grep -q "Local Codebase Analysis (fallback" "$FINDINGS_FILE" 2>/dev/null || \
        grep -q "Source type: local-fallback" "$FINDINGS_FILE" 2>/dev/null) && \
       [ -f "$PREFETCH_FILE" ] && [ "$(wc -c < "$PREFETCH_FILE")" -gt 200 ]; then
        log "  ⚠ Replacing local fallback with pre-fetched external content"
        cat > "$FINDINGS_FILE" <<HEADER
# Research Findings

> Updated: $(date '+%Y-%m-%d %H:%M')
> Source type: pre-fetched-external
> Pre-fetched from priority repos using gh

HEADER
        cat "$PREFETCH_FILE" >> "$FINDINGS_FILE"
        findings_size=$(wc -c < "$FINDINGS_FILE")
        log "  ✓ Findings now ${findings_size}B with pre-fetched content"
    fi

    # Check for actual external content (URLs, techniques, not just header)
    if grep -q "https\?://" "$FINDINGS_FILE" 2>/dev/null || \
        grep -q "## .*Technique" "$FINDINGS_FILE" 2>/dev/null; then
        log "  ✓ External research content detected"
        RESEARCH_QUALITY="external"
    elif grep -q "Source type: local-fallback" "$FINDINGS_FILE" 2>/dev/null; then
        log "  ⚠ Local fallback research generated"
        RESEARCH_QUALITY="internal"
    elif [ "$findings_size" -gt 200 ]; then
        log "  ⚠ Findings file present but may lack external content"
        RESEARCH_QUALITY="unknown"
    else
        log "  ✗ Findings file too small, research may have failed"
        RESEARCH_QUALITY="failed"
    fi
else
    log "WARNING: No findings file found at $FINDINGS_FILE"
    write_research_fallback "research findings file missing after wait"
    RESEARCH_QUALITY="internal"
fi

# Check internal research (local code patterns)
if [ -f "$INTERNAL_FILE" ]; then
    internal_size=$(wc -c < "$INTERNAL_FILE")
    log "Internal research: ${internal_size} bytes"
    if [ "$internal_size" -gt 100 ]; then
        log "  ✓ Internal code analysis available"
        if [ "$RESEARCH_QUALITY" = "none" ] || [ "$RESEARCH_QUALITY" = "failed" ]; then
            RESEARCH_QUALITY="internal"
        fi
    fi
fi

# ─── Step 2: Verify pipeline integration (file-based checks) ───
log "=== Step 2: Verify Pipeline Integration ==="
HAS_RESEARCH=0

if [ -f "$FINDINGS_FILE" ]; then
    SIZE=$(wc -c < "$FINDINGS_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100 ]; then
        log "  ✓ Findings file: $SIZE bytes"
        HAS_RESEARCH=1
    else
        log "  ⚠ Findings file too small: $SIZE bytes"
    fi
else
    log "  ⚠ Findings file missing"
fi

if [ -f "$INTERNAL_FILE" ]; then
    SIZE=$(wc -c < "$INTERNAL_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt 100 ]; then
        log "  ✓ Internal research file: $SIZE bytes"
        HAS_RESEARCH=1
    fi
fi

DIRECTIVE_FILE="$DIR/assistant/skills/auto-workflow/DIRECTIVE.md"
if [ -f "$DIRECTIVE_FILE" ]; then
    log "  ✓ Directive skill exists"
else
    log "  ⚠ Directive skill file not found"
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
        log "  ⚠ Findings are stale ($(( FINDINGS_AGE / 3600 ))h old)"
    fi
fi

# Report research quality and continue (non-fatal)
case "$RESEARCH_QUALITY" in
    external)
        log "Pipeline integration: External research available ✓"
        ;;
    internal)
        log "Pipeline integration: Internal research only (no external) ⚠"
        ;;
    unknown)
        log "Pipeline integration: Research file present but content unclear ⚠"
        ;;
    failed|none)
        log "Pipeline integration: No research available ⚠"
        ;;
esac

# Pipeline continues regardless - self-evolution can work with local data
if [ "$HAS_RESEARCH" -eq 0 ]; then
    log "WARNING: No research data available. Self-evolution will use local patterns only."
fi

# ─── Step 3: Self-Evolution (digest findings/results into skills) ───
# Pass research quality info to evolution context
export PIPELINE_RESEARCH_QUALITY="$RESEARCH_QUALITY"
export PIPELINE_FINDINGS_FILE="$FINDINGS_FILE"
export PIPELINE_INTERNAL_FILE="$INTERNAL_FILE"
run_self_evolution "Step 3: Self-Evolution (pre-workflow)"

# ─── Step 4: Auto-Workflow (uses digested findings via directive) ───
log "=== Step 4: Auto-Workflow ==="
if [ "$PIPELINE_SMOKE_ONLY" = "yes" ]; then
    log "PIPELINE_SMOKE_ONLY=yes; skipping auto-workflow batch queue"
    exit 0
fi
# Queue the workflow job (daemon will be started if not running)
auto_workflow_output="$(MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 MINIMAL_EMACS_WORKFLOW_DAEMON=1 \
    "$SCRIPT" auto-workflow 2>&1)"
printf '%s\n' "$auto_workflow_output" >> "$PIPELINE_LOG"
if printf '%s' "$auto_workflow_output" | grep -q "already-running"; then
    log "Auto-workflow already running, waiting for completion"
fi
wait_for_idle "auto-workflow" "$MAX_WAIT_WORKFLOW" "copilot-auto-workflow" || true

# Verify auto-workflow actually completed (not timed out)
workflow_status="$($SCRIPT status 2>/dev/null || true)"
if printf '%s' "$workflow_status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"'; then
    log "Auto-workflow completed successfully"
elif printf '%s' "$workflow_status" | grep -Eq ':phase "running"'; then
    log "WARNING: Auto-workflow still running after timeout; may need more time"
fi

# ─── Step 5: Self-Evolution (digest fresh workflow results) ───
if printf '%s' "$workflow_status" | grep -Eq ':phase "(idle|complete|skipped|quota-exhausted)"'; then
    run_self_evolution "Step 5: Self-Evolution (post-workflow)"
else
    log "Skipping post-workflow self-evolution because auto-workflow did not complete"
fi

# ─── Step 6: Report results ───
log "=== Pipeline Complete ==="
RESULTS_PATTERN="$DIR/var/tmp/experiments/$(date +%F)*/results.tsv"
if compgen -G "$RESULTS_PATTERN" >/dev/null; then
    latest_result=$(ls -t $RESULTS_PATTERN | head -1)
    result_count=$(wc -l < "$latest_result")
    log "Results: $latest_result ($((result_count - 1)) experiments)"
    verify_research_feedback_loop "$latest_result" || true
else
    log "No results file found for today"
fi

exit 0
