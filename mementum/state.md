# Mementum State

> **Last pipeline**: 2026-06-17 00:14 (zero-run, timeout fix verified ✓)
> **Next pipeline**: scheduled
> **Plan**: /Users/davidwu/.emacs.d/mementum/knowledge/plans/pipeline-runs/run-20260616-234849/
>
> **Bootstrapped**: 2026-06-06
> **Session**: Dual REPL Architecture (daemon-repl + Clojure brepl)
> **Status**: ✓ **TIMEOUT FIX VERIFIED + PAPER-STORYTELLING IMPLEMENTED** — Pipeline timeout fix confirmed working (completed in 26min). Implemented ljg-skills paper-storytelling cognitive framework. Self-heal hardened, world-store regressions fixed.
> **Latest**: Manual pipeline test confirmed timeout fix works: research timed out after 900s, pipeline continued with partial findings, completed all 7 steps. Implemented paper-storytelling skill (7-beat narrative spine) and research-paper-flow workflow. Hardened self-heal unused-variable fixer and fixed world-store regressions. Full ERT suite green: 3398 tests, 0 unexpected.

---

## Session Note (2026-06-16 — Self-heal _prefix corruption hardening + world-store regression fixes)

1. **Synced with remote and found regressions**
   - Remote commit `ce40a5260` fixed datahike pod availability check (was always returning nil due to `(booleanp nil)` being t).
   - After sync, full ERT suite went from green to 10 unexpected failures.
   - Also found running daemon had re-corrupted `strategic.el` (`if` → `_if`) and `prompt-analyze.el` with blank lines.

2. **Hardened self-heal unused-variable fixer** (`lisp/modules/gptel-auto-workflow-evolution.el`)
   - Root cause: `gptel-auto-workflow--fix-unused-variables` used naive regex `(\<VAR\>` on lines containing `let`/`defun`, renaming every occurrence including special forms (`if` → `_if`) and prefixes (`file-name-*` → `_file-name-*`).
   - Added blocklist for special forms and fboundp symbols.
   - Added non-symbol-next-char guard to regex so `file` rename no longer matches `file-name-nondirectory`.
   - Added TDD regression tests for `_if` and `_file-name` corruption.

3. **Fixed world-store regressions from enabled pod**
   - `parse-all-results` crashed with `wrong-type-argument sequencep 99` when brepl fallback returned a scalar.
     - Fixed by coercing only sequences and skipping non-sequence entities.
   - `ensure-nrepl` reused a global nREPL process even when tests requested a different port, causing branch tests to operate on the wrong store.
     - Added `ov5-world-store--nrepl-process-port` tracking and restart on port mismatch.
   - `ov5-world-store-branch-delete` and `ov5-world-store-branch-promote` swallowed Clojure exceptions and unconditionally returned `t`.
     - Now signal errors when brepl-eval returns nil.

4. **Verification**
   - Full ERT suite: 3398 tests, 3340 expected, 0 unexpected, 58 skipped.
   - Committed and pushed as `239dd84ec`.

---

## Session Note (2026-06-17 — Timeout fix verification)

1. **Manual pipeline test**
   - Started pipeline at 23:48:43
   - Research started at 23:48:55
   - Research timed out at 00:04:00 (900s = 15 minutes) ✓
   - Pipeline continued with partial findings ✓
   - Completed all 7 steps at 00:14:34 (total 26 minutes) ✓
   - No more hanging forever ✓

2. **Timeout fix confirmed**
   - `clj/ov5/pipeline/daemon.clj` wait-for-idle! now checks timeout BEFORE daemon alive
   - When elapsed >= max-wait-ms, logs warning and kills stuck daemon
   - Pipeline enforces 900s timeout even when daemon is stuck

3. **Issues found during test**
   - Old stuck daemon (PID 98987) from previous run had to be manually killed
   - Old stuck pmf-value-stream daemon (PID 41661) also had to be killed
   - Pipeline cleanup doesn't always kill all daemons on exit

4. **Next steps**
   - Investigate why researcher subagent gets stuck (LLM timeout? infinite loop?)
   - Add daemon cleanup on pipeline exit (ensure all daemons killed)
   - Consider implementing Fusion self-fusion (lowest-effort improvement from study)

---

## Session Note (2026-06-16 — Paper-storytelling implementation)

1. **Implemented paper-storytelling cognitive framework skill**
   - Created `assistant/skills/paper-storytelling/SKILL.md`
   - 7-beat narrative spine: protagonist → dilemma → old path → turning point → solution → ending → core
   - Speed-read card (3 lines: 一句话, 大想法, 只记三件事)
   - PhD advisor review (honest assessment)
   - Real-world testing (where it works/breaks)
   - Verification gates and Eight Keys reference

2. **Implemented research-paper-flow workflow**
   - Created `assistant/skills/research-paper-flow/SKILL.md`
   - Workflow chain: researcher → paper-storytelling
   - Automatically invoked when researcher detects paper URLs
   - 4-step procedure: initial scan → deep analysis → insights extraction → mementum storage

3. **Updated researcher-prompt skill**
   - Added paper analysis section with detection triggers (arxiv, PDF, conference links)
   - Procedure for invoking paper-storytelling
   - Output format for paper stories
   - Explanation of why storytelling > extraction

4. **Impact**
   - Transforms research from surface-level extraction to narrative understanding
   - Stories are retellable; facts are easily forgotten
   - Stories connect to existing knowledge; facts float in isolation
   - Stories reveal the *why* behind the *what*

5. **Integration**
   - Skills auto-loaded by skill-graph from assistant/skills/
   - Researcher detects paper URLs and invokes paper-storytelling
   - Stories stored in mementum/memories/paper-{title}.md
   - Actionable insights feed into experiment hypothesis generation

6. **Commits**
   - `4ac0541ac` — ⚒ implement paper-storytelling cognitive framework skill
   - `c3ea01b75` — ◈ state: paper-storytelling implementation documented

---

## Session Note (2026-06-16 — ljg-skills study and gap analysis)

1. **Studied ljg-skills** (https://github.com/lijigang/ljg-skills, 5.9k stars, 687 forks)
   - Collection of cognitive framework skills for Claude Code
   - Each skill is a structured thinking methodology, not a technical capability
   - Key skills: ljg-learn (8-dimension concept anatomy), ljg-paper (7-beat narrative spine), ljg-paper-river (recursive citation tracing), ljg-think (vertical deep-drill), ljg-roundtable (multi-persona debate)
   - Design patterns: trigger words, visual output (PNG cards, ASCII diagrams), storytelling, workflow composition, Denote integration

2. **Explored OV5 skills system** (thorough exploration via task agent)
   - 4 skill registries: assistant/skills/ (25), packages/nucleus/skills/ (8), .opencode/skills/ (7), .agents/skills/ (4)
   - 3-level hierarchy: atoms → molecules → compounds
   - Ontology-driven routing: multi-dimensional scoring (task-overlap, category-fit, keyword-depth, keep-rate, trend, confidence, holographic)
   - Skill graph: edge weights updated by experiment outcomes
   - Champion league: per-axis champions crowned by keep-rate
   - Strengths: automated evolution, ontology routing, skill graph, governance
   - Weaknesses: no cognitive frameworks, no visual output, no storytelling, no depth tools, no multi-perspective, no interactive UX

3. **Identified 6 highest-leverage gaps**
   - Gap 1: Cognitive framework skills for research (paper-storytelling, citation-tracing, concept-anatomy, deep-drill, multi-perspective)
   - Gap 2: Visual output for research (PNG cards, ASCII diagrams, org-mode reports)
   - Gap 3: Interactive skill browser (Emacs UI for skill graph visualization)
   - Gap 4: Natural language skill invocation (trigger-word system)
   - Gap 5: Workflow composition (interactive tool to chain skills)
   - Gap 6: Multi-persona research (structured debate, multi-model panels)

4. **Strategic insight**
   - ljg optimizes **human cognition** (thinking methodologies); OV5 optimizes **automated evolution** (skills improve through experiments)
   - Integration: adopt ljg's cognitive frameworks as OV5 research skills → gives OV5 both depth (8-dimension analysis) and evolution (automated improvement)
   - Best integration path: (1) cognitive framework skills, (2) trigger-word system, (3) visual output, (4) skill browser, (5) workflow composition, (6) multi-persona research

5. **Documentation created**
   - `mementum/knowledge/ljg-skills-vs-ov5-gaps.md` — full gap analysis
   - `mementum/memories/insight-ljg-skills-cognitive-frameworks.md` — key insights

---

## Session Note (2026-06-16 — Pipeline timeout fix)

1. **Discovered critical operational issue**
   - Pipeline stuck at "Waiting for research to complete" since 19:08 (2+ hours)
   - Max wait is 900s (15 minutes) but timeout never triggered
   - Researcher daemon (gtm-product-org, PID 48789) running for 2h14m
   - No research findings produced, no research traces generated
   - Pipeline process already exited but daemon kept running

2. **Root cause analysis**
   - Pipeline timeout mechanism in `clj/ov5/pipeline/daemon.clj` `wait-for-idle!` broken
   - Bug: Researcher daemon behavior checked if daemon was alive BEFORE checking timeout
   - If daemon was alive but stuck (LLM call hanging), loop continued forever
   - Timeout check only happened at start of next iteration, but elapsed never incremented
   - Result: pipeline waited 2+ hours instead of 15 minutes

3. **Immediate fix applied**
   - Killed stuck researcher daemon: `pkill -f "gtm-product-org"`
   - Verified daemon killed, no pipeline process running

4. **Code fix applied** (`clj/ov5/pipeline/daemon.clj`)
   - Moved timeout check BEFORE daemon alive check in cond chain
   - Now when elapsed >= max-wait-ms:
     - Log timeout warning
     - Call discard-stale-worker-daemon! to kill stuck daemon
     - Return :timeout immediately
   - Ensures pipeline enforces 900s timeout even when daemon is stuck

5. **Commits**
   - `1467f24d7` — ⊘ fix: pipeline timeout broken for researcher daemon
   - `d761e8695` — ◈ state: pipeline timeout fix documented

---

## Session Note (2026-06-16 — OpenRouter Fusion study)

1. **Studied OpenRouter Fusion** (https://openrouter.ai/blog/announcements/fusion-beats-frontier/)
   - Fusion dispatches research to panel of models in parallel, judge model produces structured analysis
   - DRACO benchmark (100 deep research tasks, ~39 weighted criteria, 4 categories)
   - Key results: Fable 5 + GPT-5.5 = 69.0% vs Fable 5 alone = 65.3%
   - Budget panel (Gemini 3 Flash + Kimi K2.6 + DeepSeek V4 Pro) = 64.7%, beats GPT-5.5 (60.0%)
   - Self-fusion (Opus 4.8 × 2) = 65.5% vs solo = 58.8% — 6.7pt boost from synthesis alone

2. **Explored OV5 researcher architecture** (thorough exploration via task agent)
   - Single-model dispatch (MiniMax-M3) per research session
   - AutoTTS multi-turn controller (5 decisions: STOP/CONTINUE/BRANCH/WIDEN/CUT)
   - No multi-model fusion, no cross-model verification, no structured consensus
   - Heuristic scoring (URL count, structure, length) — no DRACO benchmark
   - Strengths: strategy champion league, controller design agent, trace replay cache, mementum synthesis

3. **Identified 6 highest-leverage gaps**
   - Gap 1: Multi-model research panel (parallel dispatch + judge)
   - Gap 2: Self-fusion (same model ×2, proven 6.7pt boost) — lowest effort
   - Gap 3: Budget panel strategy (cost-aware panel from backend registry)
   - Gap 4: Structured consensus analysis (consensus, contradictions, blind spots)
   - Gap 5: Research benchmark (DRACO-like eval for research quality)
   - Gap 6: Contamination prevention (exclude eval domains from search)

4. **Strategic insight**
   - Synthesis > selection for research tasks
   - OV5 has infrastructure (backend registry, subagent dispatch) — missing fusion layer
   - Integration: add fusion as research variant in champion league

5. **Documentation created**
   - `mementum/knowledge/fusion-vs-ov5-researcher-gaps.md` — full gap analysis
   - `mementum/memories/insight-fusion-multi-model-research-beats-frontier.md` — key insights

---

## Session Note (2026-06-16 — Auto-research paper writing study)

1. **Studied auto_research paper writing skill** (https://victorchen96.github.io/auto_research/skill/paper-writing.html)
   - Auto-research models scientific paper writing as hierarchical skill group
   - 5 sub-skills: Literature Survey, Paper Structure, Experiment Design, Figures/Tables, Peer Review
   - 4 quality gates: Literature, Experiment, Structure, Figures, Final Review
   - Produces 8.5/10 survey papers autonomously through iterative review loops

2. **Identified 5 highest-leverage gaps for OV5**
   - **Gap 1: Structured literature survey** — OV5 does ad-hoc research; auto-research has 4-stage pipeline with LQS scoring
   - **Gap 2: Research quality gates** — OV5 has 7 gates for code but none for research; auto-research has 5 gates
   - **Gap 3: Peer review simulation** — OV5 has single-grader; auto-research has 5 reviewer personas with weakness routing
   - **Gap 4: Iterative improvement loop** — OV5 doesn't track score progression; auto-research progresses 6.0 → 8.5+
   - **Gap 5: Hypothesis pre-registration** — OV5 experiments lack statistical planning; auto-research requires pre-registration

3. **Strategic insight**
   - Auto-research optimizes **research quality** through structured pipelines and peer review
   - OV5 optimizes **code improvement** through experiment loops and self-healing
   - Integration opportunity: add auto-research's research pipeline to OV5's code improvement loop

4. **Implementation priority**
   - Start with structured literature survey (foundation)
   - Then research quality gates (standards)
   - Then peer review simulation (iteration driver)

5. **Documentation created**
   - `mementum/knowledge/auto-research-vs-ov5-gaps.md` — full gap analysis
   - `mementum/memories/insight-auto-research-paper-writing-gaps.md` — key insights

---

## Session Note (2026-06-16 — Duplicate daemon bug fix)

1. **Discovered critical operational issue**
   - Pipeline log showed "Auto-workflow queued: :completed" but no experiments produced
   - Status file showed `:running t :phase "running"` but daemon not responding to emacsclient
   - Found **5 duplicate pmf-value-stream daemons** and **2 duplicate gtm-product-org daemons** running simultaneously
   - All competing for the same socket, causing emacsclient timeouts

2. **Bug in `ensure-worker-daemon!`** (`clj/ov5/pipeline/daemon.clj`)
   - Function checked if daemon was alive (line 256-258)
   - But didn't return early — continued with cleanup and launch steps
   - Each pipeline run created a new daemon without killing the old one
   - Result: multiple daemons competing for same socket

3. **Fix applied**
   - Wrapped cleanup/launch code in `do`-block within `if`-else
   - Now returns `:already-running` immediately if daemon is alive
   - Prevents duplicate daemon creation

4. **Cleanup performed**
   - Killed all duplicate pmf-value-stream daemons (5 → 0)
   - Killed all duplicate gtm-product-org daemons (2 → 0)
   - Cleaned stale sockets in /tmp/emacs501/

5. **Verification**
   - Clojure syntax test passed
   - Committed as `110589252`
   - Pushed to origin and upstream

6. **Documentation created**
   - `mementum/memories/insight-researcher-daemon-stuck-timeout-broken.md` — memory of critical issue

---

*Active Mementum v1.1 — timeout fix verified, paper-storytelling implemented, ljg-skills studied, Fusion studied, auto-research studied, duplicate daemon bug fixed*
