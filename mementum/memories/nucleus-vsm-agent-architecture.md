## Nucleus VSM × Lambda for Agent Prompts

**What**: Layer AI instruction files using Stafford Beer's Viable System Model:
- S5 (Identity) → S4 (Intelligence) → S3 (Control) → S2 (Coordination) → S1 (Operations)
- Each layer uses lambda notation: `λ name(x). constraint | preference > alternative | ¬prohibition`

**Why**: Composable, self-documenting agent prompts. Higher layers anchor everything below; changes cascade predictably.

**Action for us**: Restructure `assistant/agents/` prompts using VSM layering instead of flat prompts. Already started in `nucleus-prompts.el` but not yet using VSM.

**Priority**: Medium — enables systematic agent evolution.