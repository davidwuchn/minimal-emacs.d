## Nucleus Behavior System — Key Insight

**Pattern**: Hashtag-activated mode switching with XML prompt injection.

**Core mechanism**:
- Modes (`#=code`, `#=debug`, `#=review`) are mutually exclusive
- Qualities (`#deep`, `#concise`) and techniques (`#tdd`, `#backward`) stack freely
- Hook intercepts prompts → extracts `#hashtags` → injects `behaviors/*/prompt.md` as XML blocks
- State persists in `~/.config/eca/.behaviors/{chat_id}`

**Application for gptel-auto-workflow**:
1. Create `gptel-nucleus-behaviors.el` module
2. Add `gptel-prompt-rewrite-hook` that extracts `#=mode #quality` from prompt
3. Inject boundary constraints as system-prompt additions
4. Replace ad-hoc prompt instructions with composable behavior blocks

**Priority**: Medium — adds structured mode control to the high-failure evolution module (5874 lines).
