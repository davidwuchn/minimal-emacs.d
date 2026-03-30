---
title: Emacs Daemon Auto-Workflow Lessons
date: 2026-03-30
---

# Emacs Daemon Auto-Workflow - Critical Lessons

## Problem Summary

The auto-workflow had multiple critical issues:
1. **Retry logic failing** with `wrong-number-of-arguments` errors
2. **Void function errors** for `gptel-auto-workflow--read-file-contents` during async callbacks
3. **Syntax errors** from merged function definitions
4. **Complex scope issues** in nested callbacks

## Root Causes & Solutions

### 1. Function Definition Merge (CRITICAL)
**Problem:** Two function definitions were accidentally merged together:
```elisp
;; BROKEN:
(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)

(defun gptel-auto-workflow--read-file-contents (filepath)
  ...
  "Execute shell COMMAND..."  ;; ← Wrong docstring placement!
```

**Solution:** Properly separate function definitions:
```elisp
;; FIXED:
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND..."
  ...)
```

### 2. Cross-Module Function Visibility
**Problem:** Function defined in `gptel-tools-agent.el` not visible in async callbacks from `gptel-benchmark-subagent.el`

**Solution A:** Add `require` and `declare-function`:
```elisp
;; In gptel-benchmark-subagent.el
(require 'gptel-tools-agent nil t)
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
```

**Solution B:** Add autoload cookie:
```elisp
;; In gptel-tools-agent.el
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  ...)
```

### 3. Validation Retry Type Checking
**Problem:** Retry logic failing on nil or empty validation errors

**Solution:** Add robust type checking:
```elisp
(if (and validation-error
         (stringp validation-error)           ; ← Ensure it's a string
         (> (length validation-error) 0)      ; ← Ensure not empty
         (string-match-p "..." validation-error)
         (not (bound-and-true-p gptel-auto-experiment--in-retry)))
    ;; Retry logic
    ...)
```

### 4. Over-Engineering Retry Logic
**Lesson:** Complex helper functions with symbol references and scope manipulation are error-prone

**Better Approach:** Keep it simple:
- Inline retry logic with proper type checking
- Avoid complex macro/symbol tricks
- Test incrementally

## macOS Daemon Management (launchctl)

### Proper Commands:
```bash
# Check status
launchctl list | grep emacs

# Start daemon
launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Stop daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist

# Restart daemon
launchctl unload ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist && \
  sleep 2 && \
  launchctl load ~/Library/LaunchAgents/org.gnu.emacs.daemon.plist
```

### Plist Configuration:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>org.gnu.emacs.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Emacs.app/Contents/MacOS/Emacs</string>
        <string>--daemon</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/emacs-daemon.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/emacs-daemon-error.log</string>
</dict>
</plist>
```

## Debugging Techniques

### 1. Check Syntax:
```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "lisp/modules/gptel-tools-agent.el")
    (goto-char (point-min))
    (condition-case nil
        (check-parens)
      (error (message "Syntax error"))))'
```

### 2. Count Parentheses:
```bash
python3 << 'EOF'
with open("lisp/modules/gptel-tools-agent.el", "r") as f:
    content = f.read()
print(f"Open: {content.count('(')}, Close: {content.count(')')}")
EOF
```

### 3. Find Exact Error Location:
```bash
emacs --batch --eval '
  (with-temp-buffer
    (insert-file-contents "file.el")
    (goto-char (point-min))
    (condition-case nil
        (while t (forward-sexp))
      (scan-error 
       (message "Error at line %d" (line-number-at-pos)))))'
```

## Results

After all fixes:
- ✅ **114 experiments** completed
- ✅ **10.6% success rate** (12/113 kept)
- ✅ **56 high-quality** experiments (score ≥8)
- ✅ **0 critical errors**
- ✅ **Remote synced** to main branch

## Key Principles

1. **Simplicity over complexity** - Simple type checking > complex helper functions
2. **Declare dependencies** - Use `declare-function` for cross-module calls
3. **Test incrementally** - Don't make multiple complex changes at once
4. **Use launchctl** - Proper daemon management on macOS
5. **Validate syntax** - Always check before committing