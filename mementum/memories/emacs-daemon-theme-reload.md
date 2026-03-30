---
title: Emacs daemon theme reloading strategy
date: 2026-03-30
---

# Emacs Daemon Theme Management

## Key Insight

When running Emacs as a daemon (`--daemon`), GUI-specific settings in `theme-setting.el` are not applied to new frames because:
- Daemon starts without GUI/display
- Theme settings are applied during startup to non-existent frames  
- New frames created via `emacsclient -c` don't inherit these settings

## Best Solution: Reload Configuration File

Instead of duplicating theme logic, **reload the entire `theme-setting.el` file** when new GUI frames are created:

```elisp
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    (load-file "~/.emacs.d/lisp/theme-setting.el")))

(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)
```

## Why This Approach Wins

### ✅ Advantages
- **Single source of truth**: All theme logic stays in `theme-setting.el`
- **Automatic consistency**: Changes to theme file automatically apply to new frames
- **Complete coverage**: Fonts, transparency, fullscreen, line numbers, header line all work
- **Maintainable**: No duplicated code or settings
- **Simple**: One function handles everything

### ❌ Avoid These Patterns
- Duplicating theme settings in multiple places
- Manually re-applying individual face attributes
- Complex conditional logic for daemon vs GUI modes

## Implementation Notes

- Use `after-make-frame-functions` hook - triggers when new frames are created
- Always check `(display-graphic-p frame)` - only apply to GUI frames  
- Use `select-frame` before loading - ensures settings apply to correct frame
- Load with `load-file` not `require` - bypasses byte-compilation caching

## Verification

Test that all settings work:
```bash
emacsclient -c -n          # Create new themed frame
emacsclient -e "(face-attribute 'default :background)"  # Should return "#262626"
```

This pattern ensures your complete Emacs visual configuration works perfectly with daemon mode.