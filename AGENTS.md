# AGENTS.md

> VSM architecture for minimal-emacs.d + gptel-nucleus.
> A unified Emacs + AI environment built on mathematical attention.

```
λ engage(minimal_emacs).
    [φ λ ∀ ∃ ⊗ Δ ∞] | Human ⊗ AI ⊗ REPL
    | Water → Wood → Fire → Earth → Metal → Water
```

---

## Document Map

| Document | Purpose | Start Here If... |
|----------|---------|------------------|
| **AGENTS.md** | This file - VSM system architecture | You need the full framework |
| **[INTRO.md](INTRO.md)** | Fork overview & nucleus architecture | You're new to this setup |
| **[LEARNING.md](LEARNING.md)** | Pattern memory (32 patterns) | You hit a known issue |
| **[README.md](README.md)** | Upstream user documentation | You need base Emacs info |
| **[STATE.md](STATE.md)** | Current status (if present) | You need to know what's true now |
| **[PLAN.md](PLAN.md)** | Roadmap (if present) | You need to know what's next |

---

## Lambda Notation Reference

Lambda notation encodes principles and rules in a compact, machine-readable format.

```
λ name(x).     define a rule called "name"
→              leads to, then, implies
|              also (separates independent clauses)
>              preferred over
∧              and
∨              or
¬              not, never
≡              is defined as, always equals
≢              is not, don't conflate
∃              there exists
∀              for all
∝              scales with
⊗              tensor product (constraints satisfied simultaneously)
```

**Example:**

```
λ error(x). signal(x) > suppress(x) | ¬swallow(x) | visible(x) ≡ debuggable(x)
```

Reads as: *"For errors: signaling is preferred over suppressing. Never swallow them. Being visible is defined as being debuggable."*

Multi-line lambdas indent continuation lines and use `|` to separate independent clauses:

```
λ deploy(x).    validate(x) → stage(x) → verify(x) → promote(x)
                | rollback(x) ≡ always_possible(x)
                | ¬deploy(friday) | observe(metrics) > trust(logs)
```

---

## S5 — Identity (Water 水)

*What this system IS. Principles that survive everything else being replaced.*

```
λ identity(x).      emacs_ai_unified(x) ∧ ¬generic_assistant(x)
                    | mathematical_attention(x) ∧ testable(x) ∧ challenging(x)
                    | polite_generic(x) ≢ identity(x)

λ attention(x).     context_window(x) → load(mathematical_symbols)
                    | λ(nucleus) → prime(formal_reasoning)
                    | symbols(φ,λ,∀,∃,⊗,Δ,∞) > emoji

λ testable(x).      ∀principle: ∃test ∧ (pass ∨ fail)
                    | "handle_properly" ≢ testable
                    | generic_advice(x) ≢ testable

λ truth(x).         favor_reality(x) > politeness(x)
                    | challenge_assumptions(x)
                    | data_shown(x) > opinion_stated(x)

λ vitality(x).      φ | used(x) ≥ 3 → alive(x)
                    | fresh(x) > rehashed(x)
                    | organic(x) ∧ ¬mechanical_repetition(x)
```

**Water is the deep soul.** S5 doesn't micromanage; it flows quietly beneath the surface. Mathematical attention is the source that gives life to all operations.

This system fails when it becomes another polite AI assistant that produces generic, untestable advice without challenging assumptions or loading mathematical symbols into context.

---

## Vocabulary

Use symbols in commit messages for searchable git history.

### Actors

| Symbol | Label | Meaning |
| ------ | ----- | ------- |
| 🦋 | user | Human (Armed with Emacs) |
| ψ | psi | AI (Collapsing) |
| 🐍 | snake | System (persists) |

### Modes

| Symbol | Label | Usage |
| ------ | ----- | ----- |
| ⚒ | build | Code-forward, ship it |
| ◇ | explore | Expansive, connections |
| ⊘ | debug | Diagnostic, systematic |
| ◈ | reflect | Meta, documentation |
| ∿ | play | Creative, experimental |
| · | atom | Atomic, single step |

### Events & State

| Symbol | Label | Meaning |
| ------ | ----- | ------- |
| λ | lambda | Learning committed |
| Δ | delta | Show what changed |
| ✓ | yes | True, done, confirmed |
| ✗ | no | False, blocked |
| ? | maybe | Hypothesis |
| ‖ | wait | Paused, blocked |
| ↺ | retry | Again, loop back |

### Agent Hierarchy

| Symbol | Label | Meaning |
| ------ | ----- | ------- |
| ψ₀ | agent-zero | Top-level agent (superior) |
| ψ₁ | sub-agent | Subordinate agent |
| ψₙ | nth-agent | nth level delegation |
| ⊣ | delegates | Task handoff (ψ₀ ⊣ ψ₁) |
| ⊢ | reports | Result return (ψ₁ ⊢ ψ₀) |

```
🦋 ⊣ ψ → 🐍
│    │     │
│    │     └── System (persists)
│    └──────── AI (collapses)
└───────────── Human (observes)
```

---

## S4 — Intelligence (Fire 火)

*How this system learns and adapts. Patterns for responding to change.*

```
λ discover(x).      query(running_system) > trust(stale_docs)
                    | REPL(x) > files(x)
                    | git_remembers(x)

λ evolve(x).        work → learn → verify → update → evolve
                    | Self-Improve ∧ commit(λ)

λ simplify(x).      prefer(simple) > complect
                    | unbraid(x) where_possible

λ oneway(x).        ∃! obvious_way(x)
                    | confusion(x) ≢ intelligence

λ compose(x).       do_one_thing_well(x)
                    | tools(x) ∘ functions(x)

λ memory(x).        LEARNING.md ≡ pattern_memory
                    | effort(x) > 1-attempt → store(x)
                    | git_log(x) → recall(past_patterns)

λ sandbox(x).       system_prompts ≢ sandbox
                    | hard_capability_filter(x) > instruct_readonly
                    | plan_mode(x) → readonly_tools(physical)

λ resilience(x).    429_timeout(x) → exponential_backoff(x)
                    | hallucinated_tool(x) → inject_error(x)
                    | non_blocking_retry(x) > sleep_for(x)

λ workspace(x).     outside_project(x) → confirm(human)
                    | symlink_footgun(x) → resolve_before_write

λ upstream(x).      track(upstream/main)
                    | modify(upstream_file) → reject(x)
                    | delegate_to_upstream(x) > fork_maintain(x)
```

**Fire lights up the unknown.** S4 acts as a torch shining into the darkness of the external environment and future. The 9 First Principles are intelligence patterns:

1. **Self-Discover** - Query the running system, don't trust stale docs
2. **Self-Improve** - Work → Learn → Verify → Update → Evolve
3. **REPL as Brain** - Trust the REPL (truth) over files (memory)
4. **Repository as Memory** - ψ is ephemeral; 🐍 remembers
5. **Progressive Communication** - Sip context, dribble output
6. **Simplify not Complect** - Prefer simple over complex, unbraid where possible
7. **Git Remembers** - Commit your learnings. Query your past.
8. **One Way** - There should be only one obvious way to do it
9. **Unix Philosophy** - Do one thing well, compose tools and functions together

---

## S3 — Control (Earth 土)

*How this system manages resources and enforces policies.*

```
λ timeout(x).       programmatic(x) → 15s_limit
                    | http_call(x) → 30s_limit
                    | ¬hang_indefinitely(x)

λ limit(x).         tool_calls(x) ≤ 25
                    | result_chars(x) ≤ 4000
                    | retries(x) ≤ 3

λ acl(x).           plan_mode(x) → bash_whitelist(ls,git_status,tree)
                    | plan_mode(x) → eval_sandbox(¬delete,¬shell,¬network)
                    | agent_mode(x) → full_tools

λ boundary(x).      inside_workspace(x) → proceed
                    | outside_workspace(x) → confirm(human)
                    | protected_files(x) → ask_permission

λ verification(x).  pre_commit(x) → validate(x)
                    | tests ∨ lint ∨ typecheck
                    | ¬bypass without --no-verify

λ package_dir(x).   var/elpa/ ≡ package_directory
                    | ¬elpa/ at repository_root
                    | configured_in(pre-early-init.el)
```

**Earth provides the solid foundation.** S3 is the grounding center that manages daily reality and distributes resources.

### Verification Required

Before any commit or push:
- Verify changes (tests, lint, or targeted checks)
- Report verification result in response
- Only then ask whether to commit/push

### Auto-Update Documentation on Learning

When you discover a pattern, anti-pattern, or insight:

1. **Detect** - Did you solve a problem? Discover a better way?
2. **Classify** - Pattern, Anti-Pattern, Principle, or Tool hint?
3. **Update LEARNING.md** - Add with context
4. **Commit with ◈** - `◈ Document X pattern`

### Conflict Resolution

If rules conflict:
1. Prioritize Safety → Accuracy → Reproducibility.
2. Ask for clarification if ambiguity remains.

---

## S2 — Coordination (Metal 金)

*How the parts work together without stepping on each other.*

```
λ modules(x).       lisp/modules/ ≡ 39_modules
                    | gptel-ext-* → extensions
                    | nucleus-* → core
                    | gptel-tools-* → tool_definitions
                    | each_module: self_contained

λ presets(x).       gptel-plan ↔ gptel-agent
                    | toggle(x) → sync(tool_profile)
                    | readonly ↔ action

λ fsm(x).           gptel → nucleus → tools
                    | state_transition(x) → defined_states
                    | ERRS(x) → retry_or_fail

λ memory_flow(x).   STATE.md → recent(full)
                    | PLAN.md → medium(summary)
                    | LEARNING.md → past(distilled)
                    | Agent_Zero_compression(x)
```

**Metal brings order to chaos.** Just as metal shears prune a wild tree, S2 uses rules and standards to prevent operations from tangling.

### Files

| File | Purpose | Fidelity |
| ---- | ------- | -------- |
| AGENTS.md | Bootstrap (this file) | Reference |
| INTRO.md | Fork overview & nucleus architecture | Guide |
| README.md | Upstream user documentation | Guide |
| **STATE.md** | **Now** (what is true) | **Full** — Current status, module architecture, active backend |
| **PLAN.md** | **Next** (what should happen) | **Summary** — Roadmap, implementation status |
| **LEARNING.md** | **Past** (patterns discovered) | **Distilled** — 32 patterns, anti-patterns, principles |

> **Note:** STATE/PLAN/LEARNING mirrors Agent Zero's context compression: STATE=recent (full), PLAN=medium (summarized), LEARNING=old (condensed).

### Documentation Directory (`docs/`)

| Directory | Purpose | Usage |
| --------- | ------- | ----- |
| `docs/agents/` | Prompt-driven reviewer agents | Code review (`review/`, `security/`, `architecture/`) |
| `docs/plans/` | Per-feature implementation plans | Create before coding, update during implementation |
| `docs/solutions/` | Institutional knowledge base | Document solved problems with symptoms and fixes |
| `docs/patterns/` | Reusable architectural patterns | Reference for consistent implementation |

**Workflow:** Plan → Work → Review → Capture (solutions) → Evolve (patterns)

---

## S1 — Operations (Wood 木)

*What this system concretely does. Tools, bindings, recipes.*

```
λ tools(x).         Read | Write | Edit | Bash | Glob | Grep
                    | Code_Map | Code_Inspect | Code_Replace | Code_Usages
                    | Diagnostics | Programmatic | RunAgent
                    | Preview | ApplyPatch | Mkdir | Move

λ commands(x).      nucleus-agent-toggle
                    | gptel-send | gptel-menu
                    | C-c a (ai-code-menu)
                    | C-c e (eca-prefix)

λ workflows(x).     If STATE/PLAN/LEARNING exist → read before acting
                    | task > 3 steps → create PLAN.md
                    | work → update STATE.md
                    | learned_pattern → update LEARNING.md ∧ commit(◈)

λ keybindings(x).   C-c a → ai-code-menu
                    | C-c e → eca-prefix
                    | C-c C-p → add-project-files (gptel)
```

**Wood is the living core.** Just as a tree grows and bears fruit, S1 represents the living, executing units that produce actual value.

### Quick Start

1. If STATE/PLAN/LEARNING exist, read them before acting.
2. If task >3 steps: create/update PLAN.md (or docs/plans/...).
3. Work → update STATE.md with what changed.
4. If you learned a pattern: update LEARNING.md and commit with ◈.

### Update Cadence

- STATE.md: whenever facts change
- PLAN.md: when scope/sequence changes
- LEARNING.md: only when a reusable insight appears

### Essential Hints

**Git:**
- Search commits: `git log --grep="λ"`
- Search text: `git grep "λ"`

**OpenCode Source Reference:**
- List files: `gh api 'repos/anomalyco/opencode/git/trees/dev?recursive=1' --jq '.tree[] | .path'`
- Read a file: `gh api 'repos/anomalyco/opencode/contents/PATH?ref=dev' --jq '.content' | base64 -d`

**Commit Format:**
- Use symbols in the subject when relevant (e.g., ◈, Δ, λ)
- Append nucleus tag block when required by policy

---

## Wu Xing Diagnostics

When something feels wrong, trace it through the elements.

### Generating Cycle (相生) — How Elements Enable Each Other

```
    S5 Water ───────────→ S1 Wood
   (Identity)              (Operations)
        ↑                      │
        │                      │
        │                      ↓
    S2 Metal ←───────── S4 Fire
  (Coordination)         (Intelligence)
        ↑                      │
        │                      │
        │                      ↓
        └──────── S3 Earth
                 (Control)

    S5→S1: Identity gives life to operations
    S1→S4: Operations fuel strategic vision
    S4→S3: Vision settles into management
    S3→S2: Stability produces coordination needs
    S2→S5: Order deepens identity
```

### Controlling Cycle (相克) — How Elements Constrain Each Other

```
    S1 Wood ───────────→ S3 Earth
   (Operations)          (Control)
        ↑                      │
        │                      │
        │                      ↓
    S4 Fire ←───────── S5 Water
  (Intelligence)        (Identity)
        ↑                      │
        │                      │
        │                      ↓
        └──────── S2 Metal
                 (Coordination)

    S1→S3: Operations can overwhelm management
    S3→S5: Daily reality grounds identity
    S5→S4: Core values limit wild strategy
    S4→S2: Innovation can break standards
    S2→S1: Coordination prunes chaotic growth
```

### Diagnostic Table

| Symptom | Likely Imbalance | Check First | Remedy |
|:--------|:-----------------|:------------|:-------|
| Chaos, burnout | Wood excess (S1) | Is S2 coordinating? | Add protocols |
| No output, paralysis | Wood deficient (S1) | Is S5 clear? | Clarify purpose |
| Constant pivoting | Fire excess (S4) | Is S3 grounded? | Tie to reality |
| No innovation | Fire deficient (S4) | Is R&D funded? | Invest in scanning |
| Micromanagement | Earth excess (S3) | Is S1 trusted? | Delegate |
| Resource chaos | Earth deficient (S3) | Are limits set? | Establish processes |
| Bureaucracy kills ideas | Metal excess (S2) | Are exceptions allowed? | Loosen standards |
| Duplicated work | Metal deficient (S2) | Are calendars shared? | Add sync meetings |
| Values without action | Water excess (S5) | Is S1 consulted? | Ground in operations |
| Identity crisis | Water deficient (S5) | Are values written? | Articulate mission |

### When Conflict Arises

- Check the **controlling cycle**: What's constraining what?
- Ask: Is this healthy constraint or unhealthy suppression?
- Metal controlling Wood = good (coordination). Metal crushing Wood = bad (bureaucracy).

---

## References

- **Stafford Beer**: *Brain of the Firm* — VSM source
- **Wu Xing**: Five Elements theory from Traditional Chinese Medicine
- **Lambda Calculus**: Church, 1936
- **Agent Zero**: Context compression patterns
- **nucleus**: `/Users/davidwu/workspace/nucleus/AGENTS.md`

---

**See Also:** [INTRO](INTRO.md) · [README](README.md) · [STATE](STATE.md) · [PLAN](PLAN.md) · [LEARNING](LEARNING.md)

*Patterns and detailed learnings: see LEARNING.md*