💡 **Grader hangs because model↔backend routing is mismatched.** The grader subagent timed out at 900s every experiment, so no experiments completed (2026-06-15).

**Diagnosis (verified via direct curl with the daemon's API keys):**
- DashScope backend → `coding.dashscope.aliyuncs.com` (the CODING endpoint). Requesting `qwen3.6-plus` (a general model) returns EMPTY — hangs until --max-time. The coding endpoint serves qwen-coder models, not general qwen3.x-plus.
- Fallback: DeepSeek → `api.deepseek.com` with `deepseek-v4-pro`. This model IS served, but it's a REASONING model (`reasoning_content` in the response) — slow; a full grading prompt overruns the 900s timeout.
- `deepseek-chat` on api.deepseek.com returns fast (maps to deepseek-v4-flash). A working fast option exists.

**Config reality** (`gptel--known-backends`):
- DeepSeek backend declares `(deepseek-v4-flash deepseek-v4-pro)` — both served, but pro is reasoning-slow.
- CF-Gateway (Bailian token-plan) serves `(qwen3.7-max qwen3.6-plus qwen3.6-flash deepseek-v4-pro deepseek-v4-flash kimi-k2.6 glm-5.1 MiniMax-M2.5)` — qwen3.6-plus lives HERE, not on DashScope-coding.
- Routing tables `("DeepSeek" . "deepseek-v4-pro")` in `ontology-router.el` (4 sites) + `ai-behaviors.el:1158`.

**Fix direction (needs user validation — don't blind-change, the Pi5 may differ):**
- DashScope backend should point at the GENERAL DashScope compatible-mode host (not `coding.`), OR qwen3.6-plus should route to CF-Gateway where it's actually served.
- Grader fallback should prefer a fast non-reasoning model (deepseek-chat / deepseek-v4-flash) so a single grading pass doesn't overrun the timeout.

**OV5 self-detection already works:** `[self-heal] Probe: grader BROKEN` fires on the 120s probe. What's missing is auto-remediation (reroute to a verified-fast model) — that requires knowing which models each backend serves, which this memory now records.
