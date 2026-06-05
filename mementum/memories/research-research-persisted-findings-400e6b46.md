# Research: 2026-06-04 13:58

**Strategy:** persisted-findings
**Findings hash:** 400e6b469ce20f8226fe76b181c17f894cb693f0
**Targets:** lisp/modules/gptel-tools-agent-runtime.el, staging-review, lisp/modules/gptel-tools-agent-benchmark.el
**Outcome:** 0/31 kept (0%)

**Raw Findings:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-04 10:03

Researcher result for task: External research turn 1/2

<think>
Let me analyze this task carefully.

The user is invoking me as a "researcher-prompt" skill for external research. The directive says:
- Start with own repos: gh search repos davidwuchn
- Followed by: 1-2 external references
- Budget: 53% own repos, 16% external
- Confidence threshold: 65%
- Token budget: 8000

The role is read-only research synthesis. I need to:
1. Check own repos first (davidwuchn/*)
2. Then 1-2 external references
3. Extract actionable patterns for Emacs Lisp AI agents
4. Output structured digest with JSON metadata

Let me start by checking the own repos listed in the prompt:
- nucleus (VSM, lambda notation, Wu Xing)
- mementum (Git-based AI memory)
- gptel (LLM backend integration)

I don't have access to `gh` (GitHub CLI) directly via tools, but I can use WebFetch to look at the GitHub pages. Let me also check our local codebase for context.

Let me start with parallel fetches of the three own repos and the local skill-eval to understand what we already have.

Let me first look at the local skill-eval to understand validation patterns, and then fetch the three own repos.

Actually, let me think about the most efficient approach:

1. Fetch the 3 own repos in parallel (AGENTS.md/README)
2. Check the local skill-eval skill and a couple of relevant local files
3. Synthesize

Let me also consider that the prompt notes:
- "Recent failure patterns: 10 validation/timeout errors in last 10 commits"
- "Local Research Fallback" notes suggest the research daemon has been missing
- This is a deep external discovery task

Given the time budget and tool budget, I should focus on extracting 1-2 concrete patterns per repo.

Let me start with parallel fetches.
</think>I'll execute the deep external discovery task, starting with own repos per the controller directive.<think>
Good, I have the three own repos. Let me now look at recent commits/structure of each. I should also check the local codebase briefly to understand what's already implemented, to avoid re-reporting.

Let me read the gptel detailed content (it's the largest) and also look at our local implementation of gptel to understand current patterns. The mementum result is concise enough.

Key insights so far:
1. **Nucleus**: prompt compiler (prose ↔ EDN statecharts), lambda expressions, formal grammar (EBNF), prompt debugger
2. **Mementum**: git-memory protocol with three storage types (state.md, memories, knowledge), seven operations, human governance
3. **gptel**: tool use, MCP integration, multi-modal, reasoning content, in-place usage, save/resume, introspection

Let me dig into gptel more since it has the most detail relevant to Emacs AI agents, and also check our local setup to avoid duplicates.
</think>Let me dig deeper into gptel and check our local implementation to avoid duplicates.<think>

The local paths aren't accessible. I'm running in a sandboxed environment without local file access. Let me work with what I have from the webfetches. Let me also try the nucleus deep page and check mementum's lambda spec.

Given the controller is enforcing 53% own repos and 16% external, I've already covered the three own repos. Let me do a targeted external reference to satisfy the directive, but first let me extract deeper insights from the mementum and gptel content I have.

Key observations from gptel so far:
- Tool use framework with collections
- MCP integration via mcp.el
- "Pause multi-stage requests at intermediate stage and resume later" - this is HUGE for error recovery!
- Introspection API
- Save/restore chat sessions
- In-place usage (rewrite, refactor, fill in a region)

Key observations from mementum:
- Three-tier storage: state.md (working), memories (<200 words), knowledge (synthesized docs)
- Seven operations
- Human governance layer
- Feed-forward principle

Key observations from nucleus:
- EBNF formal grammar
- EDN statecharts ↔ prose bidirectional compilation
- Lambda compiler
- Prompt debugger (interactive + automated)

For our system (Emacs AI agent auto-workflow with 7% keep rate, validation/timeout failures), the most actionable insights would be:

1. **gptel's "pause + resume multi-stage requests"** — directly applicable to our experiment pipeline that has timeout failures
2. **mementum's three-tier storage** — we already have a research/insights system but could formalize the storage distinction
3. **nucleus's prompt debugger** — automated analysis of prompts would help our 7% keep rate by catching bad prompts before they cost experiments

Let me do one more fetch to check for something novel - maybe a recent article on agent resilience or a paper. Let me also check for any specific gptel "introspection" or "tool use" patterns I should know about.

Actually, looking at the budget:
- 53% own repos (done with 3 repos)
- 16% external (need 1-2 fetches)

Let me do one targeted external search related to validation/timeout issues since that's our stated failure pattern.

</think>Let me get one targeted external reference to satisfy the directive and address the validation/timeout failure pattern.<think>

Excellent! Critical finding from gptel.org/manual.html:

> "Consider let-binding the parameters gptel-backend, gptel-model, gptel-use-tools, gptel-track-response and gptel-use-context around calls to it as required. The return value of this function is a state machine object that may be used to rerun or continue the request at a later time."

This is the **state machine return value** pattern - directly relevant to our timeout/validation failures. The skill-eval can use state machines for resume on timeout.

Also from karthink/gptel:
- gptel provides "client-side elisp tools" - LLM supplies arguments, gptel runs them in Emacs session
- "Minimal disruption" design principle

Let me do one more deep-dive into the manual to capture the tool use and resume state machine patterns fully, then write up findings.

</think>Let me fetch the gptel manual for the state machine resume pattern, and check one external on agent resilience.<think>


Let me grab the most relevant section from the gptel manual about the state machine return value - this is the key insight. I need to find the section on "gptel-request" and state machines.

</think><think>


Now let me grab the specific section on the gptel finite state machine - I need the actual code structure of the FSM.
</think>Let me read the actual FSM section details from gptel.<think>


Now I have a complete picture. The gptel FSM is gold - it has:
- Pluggable transition table with predicates
- Handlers per state
- INFO plist as the "context" (serializable!)
- Can be paused/resumed by manipulating INFO
- Process sentinel support (async handlers)
- Buffer-local FSM tracking

This is a textbook mechanism for resumable agent workflows. For our timeout/validation failure problem, this is the perfect template.

I have enough now. Let me synthesize the digest. I need to keep it under 1200 chars for the digest (per instructions point 6), but the JSON metadata at the end is separate.

Let me also consider what's NOT in our codebase already - since I can't access the local files, I'll just note that the patterns are generally novel and the FSM pattern in particular is not commonly seen in Emacs AI agents.

Time to write up. The structure should be:
- External sources (per output format - this is webfetched, so all of them are "external" but the priority was own repos)
- Local analysis (skip since no access)
- JSON metadata

Let me prioritize the highest-value insights. Given the prompt is constrained to 1200 chars for the actual digest content, I need to be ruthless.

Top 3 insights:
1. **[deep-external]** gptel FSM pattern: STATE/TABLE/HANDLERS/INFO plist, async handlers, process sentinel support. Apply: replace auto-workflow's monolithic experiment runner with FSM that can pause on timeout, save INFO to disk, resume via sentinel. Addresses validation/timeout failures.

2. **[deep-external]** mementum three-tier storage + seven operations + human governance. Apply: formalize our research/insights hierarchy as state.md (current run), memory (raw observations <200 words), knowledge (synthesized pages). Stop treating all insights as one bucket.

3. **[deep-external]** nucleus EBNF grammar + prompt debugger + bidirectional prose↔EDN compiler. Apply: add a "prompt linter" pass before experiment execution to catch common prompt-engineering errors (we have validation failures - 10/10 recent commits). Could reuse nucleus notation as a compressed prompt format for our meta-prompts.

4. **[deep-external]** External: conditional retry with error reinsertion (Skylar Payne) - feed error context back into prompt rather than blind retry. This is critical for our "naive retry = same failure" problem.

Now compose within 1200 char limit. Let me draft:

---

## External Sources

**[deep-external] gptel FSM pattern** (https://gptel.org/manual.html §10.4)
- gptel-request returns a state machine object: {STATE, TABLE, HANDLERS, INFO plist}. Handlers can be async (process sentinel). INFO is the serializable "context" — pause, persist to disk, resume later by feeding INFO back.
- **Apply**: replace auto-workflow's monolithic experiment runner with FSM (INIT→PROMPT→SEND→VALIDATE→COMMIT→DONE). On timeout, serialize INFO plist to a checkpoint file; resume from sentinel on next cycle. Directly addresses our 10/10 recent validation/timeout failures by making partial work recoverable.
- **Why novel**: standard gptel usage is interactive, not batch; we can repurpose the FSM for unattended experiment pipelines.

**[deep-external] mementum three-tier storage protocol** (https://github.com/davidwuchn/mementum)
- Three storage types — `state.md` (working, <200 words), `memories/` (raw observations, <200 words each), `knowledge/` (synthesized pages). Seven operations, human governance layer, git-native temporal search.
- **Apply**: split our `research/insights.md` flat file into the mementum hierarchy. State = current AutoTTS run, memory = per-experiment observation, knowledge = distilled strategy. Word-limit enforcement (mementum runtime in Babashka) gives us a reference for Elisp port — every memory ≤200 words forces distillation.
- **Why novel**: we currently conflate raw signals with synthesized knowledge; this forces a clear boundary that the auto-workflow currently lacks.

**[deep-external] nucleus prompt debugger + EBNF grammar** (https://github.com/davidwuchn/nucleus)
- Bidirectional prose ↔ EDN statecharts, EBNF formal grammar, prompt debugger (interactive + automated analysis). Compiles mathematical operator symbols (φ, ε, τ, π, μ, ∃, ∀) as attention magnets.
- **Apply**: add a pre-execution `prompt-lint` step that runs nucleus-style validation — length, structure, presence of tension pairs — on every experiment's prompt before sending. Auto-fail prompts that score below threshold rather than burning compute.
- **Why novel**: addresses our 7% keep rate by catching bad prompts upstream.

**[deep-external] Conditional retry with error reinsertion** (https://dasroot.net/posts/2026/02/handling-timeouts-retries-llm-systems/)
- Skylar Payne's research: feed error context back into prompt rather than blind retry. Conditional retry logic inspects error type — only retry transient errors, not validation errors. Adaptive timeouts based on historical latency.
- **Apply**: distinguish 4xx (don't retry) from 5xx/timeout (retry with backoff) in our retry layer. On validation error, append the error to the next prompt attempt instead of re-sending identical prompt. Track per-prompt latency to set adaptive timeouts.
- **Why novel**: current code likely does blind retry, which our 7% keep rate suggests isn't working.

## Local Analysis
Local filesystem read access unavailable in this session — patterns listed are net-new from external research, not filtered against existing codebase.

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": [
    "github.com/davidwuchn/nucleus",
    "github.com/davidwuchn/mementum", 
    "github.com/davidwuchn/gptel",
    "gptel.org/manual.html",
    "dasroot.net/posts/2026/02/handling-timeouts-retries-llm-systems"
  ],
  "topics_covered": [
    "fsm-based-resumable-requests",
    "three-tier-knowledge-hierarchy",
    "prompt-linting-pre-execution",
    "conditional-retry-with-error-reinsertion"
  ],
  "confidence_final": 0.78,
  "insights_count": 4,
  "tokens_estimate": 3200
}
```

Let me count chars... the digest text is around 2400 chars including the headers. That's over 1200. Let me trim.

Actually, the 1200 char limit is the actual instruction: "Max 1200 chars. Prioritize depth over breadth."

Let me trim ruthlessly. I need to be under 1200 chars for the digest content.

Let me cut each entry to its essence:

---

## External Sources

**[deep-external] gptel FSM pattern** (gptel.org/manual.html §10.4)
- gptel-request returns a state machine: {STATE, TABLE, HANDLERS, INFO}. Handlers run async via process sentinel. INFO is a serializable plist — pause, dump to disk, resume by re-injecting.
- **Apply**: replace our monolithic experiment runner with FSM (INIT→PROMPT→SEND→VALIDATE→COMMIT→DONE). On timeout, persist INFO to checkpoint; resume via sentinel. Targets 10/10 recent validation/timeout failures.

**[deep-external] mementum three-tier hierarchy** (github.com/davidwuchn/mementum)
- state.md (working) / memories/ (raw obs, ≤200 words) / knowledge/ (synthesized). Word-limit forces distillation; git-native temporal search.
- **Apply**: split flat `research/insights.md` into the hierarchy. Use mementum's word-limit enforcement (Babashka runtime has a blueprint) to force distillation in Elisp.

**[deep-external] nucleus prompt debugger** (github.com/davidwuchn/nucleus)
- EBNF grammar, prose↔EDN compiler, automated prompt analysis. Mathematical operator symbols act as attention magnets.
- **Apply**: pre-execution `prompt-lint` step — length, structure, tension-pair checks — auto-failing low-quality prompts before they cost experiments. Targets 7% keep rate.

**[deep-external] Conditional retry with error reinsertion** (dasroot.net/2026/02 timeout-retry)
- Distinguish transient (retry with backoff+jitter) from validation errors (reinsert error into next prompt, don't blindly retry). Adaptive timeouts from historical latency.
- **Apply**: split our retry path by HTTP class; on validation error append the error message to the next attempt's prompt context.

## Local Analysis
Local filesystem read access unavailable in this run; insights are net-new, not filtered against current code.

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","gptel.org/manual.html","dasroot.net/2026/02/handling-timeouts-retries-llm-systems"],
  "topics_covered": ["fsm-checkpoint-resume","three-tier-knowledge","prompt-pre-lint","conditional-retry-error-reinsertion"],
  "confidence_final": 0.78,
  "insights_count": 4,
  "tokens_estimate": 1800
}
```

Let me count the digest (everything before the JSON):
- ## External Sources: ~20 chars
- **[deep-external] gptel FSM pattern** entry: ~430 chars
- **[deep-external] mementum three-tier hierarchy** entry: ~360 chars
- **[deep-external] nucleus prompt debugger** entry: ~310 chars
- **[deep-external] Conditional retry with error reinsertion** entry: ~340 chars
- ## Local Analysis: ~130 chars

Total: ~1590 chars. Still over. Let me trim more aggressively.

Actually wait - the prompt says "Max 1200 chars" but that might apply to the *insights*, not headers. Let me be conservative and cut further.

Let me try to be very tight:

---

## External Sources

**[deep-external] gptel FSM resume** (gptel.org/manual.html §10.4)
- gptel-request returns FSM {STATE, TABLE, HANDLERS, INFO plist}. Handlers async via process sentinel. INFO is serializable — persist, resume later.
- **Apply**: replace monolithic experiment runner with FS
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/var/tmp/gptel-subagent-result-7Z49tL.txt. Use Read tool if you need more]...

**Digested Insights:**

> Project: /Users/davidwu/.emacs.d/
> Updated: 2026-06-04 10:03

Researcher result for task: External research turn 1/2

<think>
Let me analyze this task carefully.

The user is invoking me as a "researcher-prompt" skill for external research. The directive says:
- Start with own repos: gh search repos davidwuchn
- Followed by: 1-2 external references
- Budget: 53% own repos, 16% external
- Confidence threshold: 65%
- Token budget: 8000

The role is read-only research synthesis. I need to:
1. Check own repos first (davidwuchn/*)
2. Then 1-2 external references
3. Extract actionable patterns for Emacs Lisp AI agents
4. Output structured digest with JSON metadata

Let me start by checking the own repos listed in the prompt:
- nucleus (VSM, lambda notation, Wu Xing)
- mementum (Git-based AI memory)
- gptel (LLM backend integration)

I don't have access to `gh` (GitHub CLI) directly via tools, but I can use WebFetch to look at the GitHub pages. Let me also check our local codebase for context.

Let me start with parallel fetches of the three own repos and the local skill-eval to understand what we already have.

Let me first look at the local skill-eval to understand validation patterns, and then fetch the three own repos.

Actually, let me think about the most efficient approach:

1. Fetch the 3 own repos in parallel (AGENTS.md/README)
2. Check the local skill-eval skill and a couple of relevant local files
3. Synthesize

Let me also consider that the prompt notes:
- "Recent failure patterns: 10 validation/timeout errors in last 10 commits"
- "Local Research Fallback" notes suggest the research daemon has been missing
- This is a deep external discovery task

Given the time budget and tool budget, I should focus on extracting 1-2 concrete patterns per repo.

Let me start with parallel fetches.
</think>I'll execute the deep external discovery task, starting with own repos per the controller directive.<think>
Good, I have the three own repos. Let me now look at recent commits/structure of each. I should also check the local codebase briefly to understand what's already implemented, to avoid re-reporting.

Let me read the gptel detailed content (it's the largest) and also look at our local implementation of gptel to understand current patterns. The mementum result is concise enough.

Key insights so far:
1. **Nucleus**: prompt compiler (prose ↔ EDN statecharts), lambda expressions, formal grammar (EBNF), prompt debugger
2. **Mementum**: git-memory protocol with three storage types (state.md, memories, knowledge), seven operations, human governance
3. **gptel**: tool use, MCP integration, multi-modal, reasoning content, in-place usage, save/resume, introspection

Let me dig into gptel more since it has the most detail relevant to Emacs AI agents, and also check our local setup to avoid duplicates.
</think>Let me dig deeper into gptel and check our local implementation to avoid duplicates.<think>

The local paths aren't accessible. I'm running in a sandboxed environment without local file access. Let me work with what I have from the webfetches. Let me also try the nucleus deep page and check mementum's lambda spec.

Given the controller is enforcing 53% own repos and 16% external, I've already covered the three own repos. Let me do a targeted external reference to satisfy the directive, but first let me extract deeper insights from the mementum and gptel content I have.

Key observations from gptel so far:
- Tool use framework with collections
- MCP integration via mcp.el
- "Pause multi-stage requests at intermediate stage and resume later" - this is HUGE for error recovery!
- Introspection API
- Save/restore chat sessions
- In-place usage (rewrite, refactor, fill in a region)

Key observations from mementum:
- Three-tier storage: state.md (working), memories (<200 words), knowledge (synthesized docs)
- Seven operations
- Human governance layer
- Feed-forward principle

Key observations from nucleus:
- EBNF formal grammar
- EDN statecharts ↔ prose bidirectional compilation
- Lambda compiler
- Prompt debugger (interactive + automated)

For our system (Emacs AI agent auto-workflow with 7% keep rate, validation/timeout failures), the most actionable insights would be:

1. **gptel's "pause + resume multi-stage requests"** — directly applicable to our experiment pipeline that has timeout failures
2. **mementum's three-tier storage** — we already have a research/insights system but could formalize the storage distinction
3. **nucleus's prompt debugger** — automated analysis of prompts would help our 7% keep rate by catching bad prompts before they cost experiments

Let me do one more fetch to check for something novel - maybe a recent article on agent resilience or a paper. Let me also check for any specific gptel "introspection" or "tool use" patterns I should know about.

Actually, looking at the budget:
- 53% own repos (done with 3 repos)
- 16% external (need 1-2 fetches)

Let me do one targeted external search related to validation/timeout issues since that's our stated failure pattern.

</think>Let me get one targeted external reference to satisfy the directive and address the validation/timeout failure pattern.<think>

Excellent! Critical finding from gptel.org/manual.html:

> "Consider let-binding the parameters gptel-backend, gptel-model, gptel-use-tools, gptel-track-response and gptel-use-context around calls to it as required. The return value of this function is a state machine object that may be used to rerun or continue the request at a later time."

This is the **state machine return value** pattern - directly relevant to our timeout/validation failures. The skill-eval can use state machines for resume on timeout.

Also from karthink/gptel:
- gptel provides "client-side elisp tools" - LLM supplies arguments, gptel runs them in Emacs session
- "Minimal disruption" design principle

Let me do one more deep-dive into the manual to capture the tool use and resume state machine patterns fully, then write up findings.

</think>Let me fetch the gptel manual for the state machine resume pattern, and check one external on agent resilience.<think>


Let me grab the most relevant section from the gptel manual about the state machine return value - this is the key insight. I need to find the section on "gptel-request" and state machines.

</think><think>


Now let me grab the specific section on the gptel finite state machine - I need the actual code structure of the FSM.
</think>Let me read the actual FSM section details from gptel.<think>


Now I have a complete picture. The gptel FSM is gold - it has:
- Pluggable transition table with predicates
- Handlers per state
- INFO plist as the "context" (serializable!)
- Can be paused/resumed by manipulating INFO
- Process sentinel support (async handlers)
- Buffer-local FSM tracking

This is a textbook mechanism for resumable agent workflows. For our timeout/validation failure problem, this is the perfect template.

I have enough now. Let me synthesize the digest. I need to keep it under 1200 chars for the digest (per instructions point 6), but the JSON metadata at the end is separate.

Let me also consider what's NOT in our codebase already - since I can't access the local files, I'll just note that the patterns are generally novel and the FSM pattern in particular is not commonly seen in Emacs AI agents.

Time to write up. The structure should be:
- External sources (per output format - this is webfetched, so all of them are "external" but the priority was own repos)
- Local analysis (skip since no access)
- JSON metadata

Let me prioritize the highest-value insights. Given the prompt is constrained to 1200 chars for the actual digest content, I need to be ruthless.

Top 3 insights:
1. **[deep-external]** gptel FSM pattern: STATE/TABLE/HANDLERS/INFO plist, async handlers, process sentinel support. Apply: replace auto-workflow's monolithic experiment runner with FSM that can pause on timeout, save INFO to disk, resume via sentinel. Addresses validation/timeout failures.

2. **[deep-external]** mementum three-tier storage + seven operations + human governance. Apply: formalize our research/insights hierarchy as state.md (current run), memory (raw observations <200 words), knowledge (synthesized pages). Stop treating all insights as one bucket.

3. **[deep-external]** nucleus EBNF grammar + prompt debugger + bidirectional prose↔EDN compiler. Apply: add a "prompt linter" pass before experiment execution to catch common prompt-engineering errors (we have validation failures - 10/10 recent commits). Could reuse nucleus notation as a compressed prompt format for our meta-prompts.

4. **[deep-external]** External: conditional retry with error reinsertion (Skylar Payne) - feed error context back into prompt rather than blind retry. This is critical for our "naive retry = same failure" problem.

Now compose within 1200 char limit. Let me draft:

---

## External Sources

**[deep-external] gptel FSM pattern** (https://gptel.org/manual.html §10.4)
- gptel-request returns a state machine object: {STATE, TABLE, HANDLERS, INFO plist}. Handlers can be async (process sentinel). INFO is the serializable "context" — pause, persist to disk, resume later by feeding INFO back.
- **Apply**: replace auto-workflow's monolithic experiment runner with FSM (INIT→PROMPT→SEND→VALIDATE→COMMIT→DONE). On timeout, serialize INFO plist to a checkpoint file; resume from sentinel on next cycle. Directly addresses our 10/10 recent validation/timeout failures by making partial work recoverable.
- **Why novel**: standard gptel usage is interactive, not batch; we can repurpose the FSM for unattended experiment pipelines.

**[deep-external] mementum three-tier storage protocol** (https://github.com/davidwuchn/mementum)
- Three storage types — `state.md` (working, <200 words), `memories/` (raw observations, <200 words each), `knowledge/` (synthesized pages). Seven operations, human governance layer, git-native temporal search.
- **Apply**: split our `research/insights.md` flat file into the mementum hierarchy. State = current AutoTTS run, memory = per-experiment observation, knowledge = distilled strategy. Word-limit enforcement (mementum runtime in Babashka) gives us a reference for Elisp port — every memory ≤200 words forces distillation.
- **Why novel**: we currently conflate raw signals with synthesized knowledge; this forces a clear boundary that the auto-workflow currently lacks.

**[deep-external] nucleus prompt debugger + EBNF grammar** (https://github.com/davidwuchn/nucleus)
- Bidirectional prose ↔ EDN statecharts, EBNF formal grammar, prompt debugger (interactive + automated analysis). Compiles mathematical operator symbols (φ, ε, τ, π, μ, ∃, ∀) as attention magnets.
- **Apply**: add a pre-execution `prompt-lint` step that runs nucleus-style validation — length, structure, presence of tension pairs — on every experiment's prompt before sending. Auto-fail prompts that score below threshold rather than burning compute.
- **Why novel**: addresses our 7% keep rate by catching bad prompts upstream.

**[deep-external] Conditional retry with error reinsertion** (https://dasroot.net/posts/2026/02/handling-timeouts-retries-llm-systems/)
- Skylar Payne's research: feed error context back into prompt rather than blind retry. Conditional retry logic inspects error type — only retry transient errors, not validation errors. Adaptive timeouts based on historical latency.
- **Apply**: distinguish 4xx (don't retry) from 5xx/timeout (retry with backoff) in our retry layer. On validation error, append the error to the next prompt attempt instead of re-sending identical prompt. Track per-prompt latency to set adaptive timeouts.
- **Why novel**: current code likely does blind retry, which our 7% keep rate suggests isn't working.

## Local Analysis
Local filesystem read access unavailable in this session — patterns listed are net-new from external research, not filtered against existing codebase.

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": [
    "github.com/davidwuchn/nucleus",
    "github.com/davidwuchn/mementum", 
    "github.com/davidwuchn/gptel",
    "gptel.org/manual.html",
    "dasroot.net/posts/2026/02/handling-timeouts-retries-llm-systems"
  ],
  "topics_covered": [
    "fsm-based-resumable-requests",
    "three-tier-knowledge-hierarchy",
    "prompt-linting-pre-execution",
    "conditional-retry-with-error-reinsertion"
  ],
  "confidence_final": 0.78,
  "insights_count": 4,
  "tokens_estimate": 3200
}
```

Let me count chars... the digest text is around 2400 chars including the headers. That's over 1200. Let me trim.

Actually, the 1200 char limit is the actual instruction: "Max 1200 chars. Prioritize depth over breadth."

Let me trim ruthlessly. I need to be under 1200 chars for the digest content.

Let me cut each entry to its essence:

---

## External Sources

**[deep-external] gptel FSM pattern** (gptel.org/manual.html §10.4)
- gptel-request returns a state machine: {STATE, TABLE, HANDLERS, INFO}. Handlers run async via process sentinel. INFO is a serializable plist — pause, dump to disk, resume by re-injecting.
- **Apply**: replace our monolithic experiment runner with FSM (INIT→PROMPT→SEND→VALIDATE→COMMIT→DONE). On timeout, persist INFO to checkpoint; resume via sentinel. Targets 10/10 recent validation/timeout failures.

**[deep-external] mementum three-tier hierarchy** (github.com/davidwuchn/mementum)
- state.md (working) / memories/ (raw obs, ≤200 words) / knowledge/ (synthesized). Word-limit forces distillation; git-native temporal search.
- **Apply**: split flat `research/insights.md` into the hierarchy. Use mementum's word-limit enforcement (Babashka runtime has a blueprint) to force distillation in Elisp.

**[deep-external] nucleus prompt debugger** (github.com/davidwuchn/nucleus)
- EBNF grammar, prose↔EDN compiler, automated prompt analysis. Mathematical operator symbols act as attention magnets.
- **Apply**: pre-execution `prompt-lint` step — length, structure, tension-pair checks — auto-failing low-quality prompts before they cost experiments. Targets 7% keep rate.

**[deep-external] Conditional retry with error reinsertion** (dasroot.net/2026/02 timeout-retry)
- Distinguish transient (retry with backoff+jitter) from validation errors (reinsert error into next prompt, don't blindly retry). Adaptive timeouts from historical latency.
- **Apply**: split our retry path by HTTP class; on validation error append the error message to the next attempt's prompt context.

## Local Analysis
Local filesystem read access unavailable in this run; insights are net-new, not filtered against current code.

```json
{
  "strategy_used": "own-repos-first",
  "sources_checked": ["davidwuchn/nucleus","davidwuchn/mementum","davidwuchn/gptel","gptel.org/manual.html","dasroot.net/2026/02/handling-timeouts-retries-llm-systems"],
  "topics_covered": ["fsm-checkpoint-resume","three-tier-knowledge","prompt-pre-lint","conditional-retry-error-reinsertion"],
  "confidence_final": 0.78,
  "insights_count": 4,
  "tokens_estimate": 1800
}
```

Let me count the digest (everything before the JSON):
- ## External Sources: ~20 chars
- **[deep-external] gptel FSM pattern** entry: ~430 chars
- **[deep-external] mementum three-tier hierarchy** entry: ~360 chars
- **[deep-external] nucleus prompt debugger** entry: ~310 chars
- **[deep-external] Conditional retry with error reinsertion** entry: ~340 chars
- ## Local Analysis: ~130 chars

Total: ~1590 chars. Still over. Let me trim more aggressively.

Actually wait - the prompt says "Max 1200 chars" but that might apply to the *insights*, not headers. Let me be conservative and cut further.

Let me try to be very tight:

---

## External Sources

**[deep-external] gptel FSM resume** (gptel.org/manual.html §10.4)
- gptel-request returns FSM {STATE, TABLE, HANDLERS, INFO plist}. Handlers async via process sentinel. INFO is serializable — persist, resume later.
- **Apply**: replace monolithic experiment runner with FS
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/var/tmp/gptel-subagent-result-7Z49tL.txt. Use Read tool if you need more]...

**Meta-learning:** Research quality measured by downstream experiment success.

---
*Generated by auto-workflow*
