# Auto-Workflow E2E Debug Session - 2026-04-02

## Issues Found and Fixed

### Issue 1: gptel.el Parsing Error ✅ FIXED

**Error:** `End of file during parsing: gptel.el`

**Cause:** gptel submodule was in detached HEAD state at old commit

**Fix:**
```bash
cd packages/gptel
git checkout master
git add packages/gptel
git commit -m "⬆️ Update gptel submodule to master"
```

### Issue 2: gptel--tool-preview-alist Void ✅ FIXED

**Error:** `Symbol's value as variable is void: gptel--tool-preview-alist`

**Cause:** Variable defined inside function in gptel.el, not at top level

**Fix:**
1. Added forward declaration in `gptel-tools-agent.el`:
   ```elisp
   (defvar gptel--tool-preview-alist nil)  ; defined in gptel.el
   ```
2. Restarted daemon to clear cached state

### Issue 3: Duplicate Function Definition ✅ FIXED

**Error:** `void-function gptel-auto-workflow--with-error-handling`

**Cause:** 
- Function renamed to `gptel-auto-workflow--safe-call`
- Old name still referenced in 4 places
- Duplicate definition in file

**Fix:**
```elisp
;; Replaced all occurrences
(gptel-auto-workflow--with-error-handling ...) 
→ (gptel-auto-workflow--safe-call ...)
```

### Issue 4: nucleus-gptel-agent Preset Not Found 🟡 PARTIAL

**Error:** `Cannot find preset gptel-agent`

**Cause:** 
- `gptel--apply-preset` tries to apply `'gptel-agent` preset
- `nucleus--override-gptel-agent-presets` should redirect to `nucleus-gptel-agent`
- But nucleus presets module not loaded in daemon

**Attempted Fixes:**
1. Loaded nucleus-presets.el manually - preset still not created
2. Called `nucleus--override-gptel-agent-presets` - returns nil

**Status:** Needs investigation of why override function fails

### Issue 5: Agent Tool Not Found 🔴 BLOCKING

**Error:** `Cannot find tool "Agent"`

**Cause:** Agent tool not registered in tool registry

**Investigation Needed:**
1. Check if gptel-agent-tools.el is loaded
2. Verify tool registration happened
3. Check if preset tool list is correct

## Current State

### What Works

✅ Daemon starts successfully
✅ gptel.el loads without errors
✅ nucleus modules load
✅ Workflow queued and starts
✅ Experiments begin execution

### What Doesn't Work

❌ nucleus-gptel-agent preset not created
❌ Agent tool not found
❌ Executor fails immediately

## Root Cause Analysis

### The Override Chain

```
1. gptel--apply-preset called with 'gptel-agent
2. Should redirect to 'nucleus-gptel-agent
3. nucleus-gptel-agent should have Agent tool
4. But nucleus-gptel-agent doesn't exist
```

### Missing Dependencies

The daemon loads minimal Emacs configuration, not the full user config. Need to ensure:

1. **gptel-agent package loaded** - ✓ (in load-path)
2. **nucleus-tools loaded** - ✓ (loaded manually)
3. **nucleus-prompts loaded** - ✓ (loaded manually)
4. **nucleus-presets loaded** - ✓ (loaded manually)
5. **nucleus-gptel-agent preset created** - ✗ (fails)

### Why Preset Creation Fails

```elisp
(defun nucleus--override-gptel-agent-presets ()
  (when (and (fboundp 'gptel-get-preset)
             (fboundp 'gptel-make-preset))
    ;; This when block returns nil if functions not bound
```

**Hypothesis:** `gptel-make-preset` doesn't exist in the gptel version we have

## Next Investigation Steps

### Step 1: Check gptel-make-preset

```bash
emacsclient -s copilot-auto-workflow --eval "(fboundp 'gptel-make-preset)"
```

If nil, need to check gptel version or define it

### Step 2: Check nucleus-agents-dir

```bash
emacsclient -s copilot-auto-workflow --eval "nucleus-agents-dir"
```

If nil, prompts not loaded properly

### Step 3: Check gptel-agent tools

```bash
emacsclient -s copilot-auto-workflow --eval "(boundp 'gptel-agent--tools)"
```

If nil, gptel-agent-tools not loaded

### Step 4: Alternative Approach

Instead of relying on preset override, directly configure in auto-workflow:

```elisp
;; In gptel-auto-workflow-projects.el
(when (fboundp 'gptel-add-tool)
  (gptel-add-tool "Agent" ...))
```

## Workaround Options

### Option 1: Use gptel-agent Preset Directly

The `gptel-agent` preset exists and has Agent tool. Skip nucleus override:

```elisp
;; In gptel-auto-workflow-projects.el, line 91
(gptel--apply-preset
 'gptel-agent  ; Use this directly
 (lambda (sym val) (set (make-local-variable sym) val)))
```

### Option 2: Define Agent Tool Manually

```elisp
(when (fboundp 'gptel-add-tool)
  (gptel-add-tool 
   "Agent"
   :function #'gptel-agent--task
   :args ...))
```

### Option 3: Load Full Emacs Config

Start daemon with full config instead of minimal:

```bash
emacs --daemon=copilot-auto-workflow
# Instead of:
MINIMAL_EMACS_ALLOW_SECOND_DAEMON=1 emacs --bg-daemon=copilot-auto-workflow
```

## Files Modified

- `lisp/modules/gptel-tools-agent.el`:
  - Added `defvar gptel--tool-preview-alist`
  - Removed duplicate `gptel-auto-workflow--safe-call`
  - Replaced `gptel-auto-workflow--with-error-handling` → `gptel-auto-workflow--safe-call`

- `packages/gptel`:
  - Updated to master branch (buffer validation fixes)

## Lessons Learned

1. **Forward declarations matter** - Variables defined in functions need `defvar` at top level
2. **Daemon state persists** - Need to restart to clear cached errors
3. **Load order is critical** - nucleus modules must be loaded in correct sequence
4. **Minimal config limitations** - Daemon doesn't get full user config, missing some setup

---

**Debug session:** 2026-04-02 11:00-12:00
**Status:** Partially fixed, Agent tool issue blocking
**Next:** Investigate gptel-make-preset and tool registration