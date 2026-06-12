# Launch Fast Chrome Extension Pattern

**Context:** Studied [launchfastlegacyx.com](https://launchfastlegacyx.com/) — an Amazon seller Chrome extension that overlays market intelligence (revenue, BSR, margins, supplier info) directly onto product and search pages.

**Key insight:** Launch Fast exemplifies the **contextual overlay pattern** — surface decision-critical data at the point of action, not in a separate tool. For OV5, the equivalent is overlaying experiment history, keep-rate, file grade, and related memories onto the files being edited in Emacs.

**Highest-leverage gap:** `gptel-file-intel-mode` — a minor mode that shows per-file experiment data (keep-rate, last outcome, best strategy) in the header-line or a side panel. Files get an A-F grade based on experiment success rate, test coverage, and staleness.

**Other gaps:**
- Risk warning before editing files with unstable baselines or pending audit issues
- Inline memory recall — show related mementum memories when editing a file
- Category/semantic cluster neighbors in side panel

**Full analysis:** `mementum/knowledge/launch-fast-vs-ov5-gaps.md`

**Symbol:** 💡
