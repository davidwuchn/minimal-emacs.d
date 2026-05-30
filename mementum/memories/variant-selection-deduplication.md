## Variant Selection Deduplication

In `gptel-auto-workflow-strategic.el`, four functions had near-identical logic:
- `gptel-auto-workflow--select-best-research-variant` / `--select-best-digest-variant`
- `gptel-auto-workflow--load-research-variant-content` / `--load-digest-variant-content`

**Refactoring**: Extracted two generic helpers:
- `gptel-auto-workflow--select-variant(subdir tag)` - champion league selection with 20% explore. Takes a strategy subdirectory name and a tag for log messages.
- `gptel-auto-workflow--load-variant-content(subdir variant-name)` - file loading with nil guard.

Original functions became thin 1-line wrappers. Net -6 lines, improved fractal Clarity (explicit abstraction), φ Vitality (one place to fix), and ∀ Vigilance (changes propagate to both variant types).

**Key insight**: When two functions differ only in a string parameter (directory name), extract a generic helper with that parameter. Use `#'file-name-sans-extension` instead of `(lambda (f) (file-name-sans-extension f))` for cleaner code.

**Placement**: Helpers defined before the wrappers at ~line 869 in the strategic module.