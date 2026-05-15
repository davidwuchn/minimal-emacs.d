# 💡 ml-intern: Doom Loop Detection Pattern

**Source:** `davidwuchn/ml-intern` — HuggingFace's open-source ML engineer agent

## Pattern: Repetition Guard

ml-intern implements a "doom loop detector" that catches repeated tool call patterns and injects corrective prompts:

### Detection Logic (`doom_loop.py`)

1. **Tool Call Signatures**: Hash of `(tool_name, args_hash, result_hash)`
   - Normalizes JSON args (sort_keys, compact separators) before hashing
   - Includes result hash so legitimate polling (same args, different results) isn't flagged

2. **Detection Modes**:
   - **Identical consecutive**: Same tool + args + result 3+ times → `[SYSTEM: REPETITION GUARD]`
   - **Repeating sequence**: Pattern like `[A,B,A,B]` with 2+ repetitions → sequence flagged

3. **Corrective Prompt Injection**:
   ```
   [SYSTEM: REPETITION GUARD] You have called '{tool_name}' with the same
   arguments multiple times in a row. STOP repeating this approach.
   Consider: using a different tool, changing arguments, or asking for guidance.
   ```

### Architecture Integration (`agent_loop.py`)

- Called **before each LLM call** in the agentic loop
- If doom detected → inject user message with corrective prompt → continue loop
- Logs to `tool_log` event for frontend visibility
- Malformed tool args also detected separately (repeated JSON parse failures)

## Application to AutoTTS Controller

Current AutoTTS controller lacks doom loop protection. Could apply:

1. **Controller decision doom**: Same `(decision, ema-conf, ema-delta)` 3+ times → force BRANCH or inject meta-prompt
2. **Researcher doom**: Same topic + source + confidence pattern → force topic switch or stop
3. **Tool call doom**: Researcher calling same search query repeatedly → inject corrective prompt

### Implementation Sketch

```elisp
(defun gptel-auto-workflow--detect-controller-doom ()
  "Check if controller is stuck in repeated decision pattern.
Returns corrective prompt or nil."
  (let ((history (seq-take gptel-auto-workflow--decision-history 10)))
    ;; Check for identical consecutive decisions
    (when (and history (>= (length history) 3))
      (let ((recent (seq-take history 3)))
        (when (apply #'equal recent)
          "[SYSTEM: Controller stuck] Same decision 3+ times. Force BRANCH or STOP.")))))
```

## Key Insight

The doom loop detector is a **meta-level controller** that monitors the agent's behavior, not just the task state. It injects corrective prompts BEFORE the agent wastes more iterations. This is a form of **meta-cognitive monitoring** that could improve AutoTTS efficiency.

**Related patterns:**
- AutoTTS EMA momentum (trend-based stopping)
- gptel-auto-workflow--controller-decide-research-flow (decision logic)
- gptel-sandbox (bounded execution)

**Tags:** doom-loop, repetition-guard, meta-cognitive, agent-monitoring, efficiency