---
title: Pattern Memory
status: active
category: knowledge
tags: [patterns, anti-patterns, principles, elisp, gptel, nucleus]
related: [mementum/knowledge/nucleus-patterns.md]
---

# Pattern Memory

Curated patterns, anti-patterns, and principles discovered through development.
Migrated from LEARNING.md (32 patterns).

## Table of Contents

- [gptel-agent & Emacs LSP (Eglot) Integration](#gptel-agent--emacs-lsp-eglot-integration)
- [AI Agent Sandboxing & Security](#ai-agent-sandboxing--security)
- [Network Resilience & LLM Edge Cases](#network-resilience--llm-edge-cases)
- [Emacs Lisp Quirks](#emacs-lisp-quirks)
- [Delegation & Context Boundaries](#delegation--context-boundaries)
- [API & Network Limitations](#api--network-limitations)
- [Feature Evaluation Discipline](#feature-evaluation-discipline)
- [Tree-sitter Language Patterns](#tree-sitter-language-patterns)
- [Emacs Byte-Compilation Traps](#emacs-byte-compilation-traps)
- [Upstream Init File Discipline](#upstream-init-file-discipline)
- [Nucleus Header Convention](#nucleus-header-convention)
- [Symlink Footguns & Data Directory Hygiene](#symlink-footguns--data-directory-hygiene)
- [Emacs Batch Init Chain](#emacs-batch-init-chain)
- [Path Resolution in minimal-emacs.d](#path-resolution-in-minimal-emacsd)
- [Discovery Pattern (λ)](#discovery-pattern-λ)
- [Tool Argument Naming Conventions](#tool-argument-naming-conventions)
- [Confirmation UI Architecture](#confirmation-ui-architecture)
- [ECA Bridge Integration Patterns](#eca-bridge-integration-patterns)
- [Multi-Project Workspace Patterns](#multi-project-workspace-patterns)
- [ai-code-menu Transient Integration](#ai-code-menu-transient-integration)
- [Auto-Detection Patterns](#auto-detection-patterns)
- [Upstream Delegation vs Local Extensions](#upstream-delegation-vs-local-extensions)
- [TDD Refactoring Workflow](#tdd-refactoring-workflow)
- [Backend Integration Patterns](#backend-integration-patterns)
- [Context Window Detection & Auto-Compact](#context-window-detection--auto-compact)
- [Emacs Lisp Pattern Matching (pcase)](#emacs-lisp-pattern-matching-pcase)
- [Context Management Code Organization](#context-management-code-organization)
- [VSM Architecture Pattern](#vsm-architecture-pattern)
- [Package VC Installation Pitfalls](#package-vc-installation-pitfalls)
- [gptel/gptel-agent Version Compatibility](#gptelgptel-agent-version-compatibility)
- [Per-Preset Model Configuration](#per-preset-model-configuration)
- [Deferred Package Loading for Performance](#deferred-package-loading-for-performance)
- [Upstream Directory Structure Compliance](#upstream-directory-structure-compliance)
- [Context Window Cache Maintenance](#context-window-cache-maintenance)

---

## gptel-agent & Emacs LSP (Eglot) Integration

- **Asynchronous JSON-RPC**: Bypassing Emacs interactive UI commands (like `xref-find-definitions`) and querying the LSP server directly via `jsonrpc-async-request` is significantly more efficient and reliable for an AI agent.
- **Server Resolution**: `(eglot-current-server)` can return `nil` if called immediately after `(find-file-noselect ...)` because the server attaches asynchronously. A more robust method is to resolve the project and lookup the server in `eglot--servers-by-project`.
- **Project-Wide Diagnostics**: Iterating over `(buffer-list)` and calling `(flymake-diagnostics)` only yields errors for *open* files. Emacs 29+ provides `(flymake--project-diagnostics)`, which correctly queries the LSP for the entire project's error state, including closed files.
- **0-Indexed vs 1-Indexed**: LSP locations (lines/characters) are 0-indexed, whereas Emacs lines are 1-indexed. Agent tool prompts must explicitly state which indexing system they expect to prevent coordinate drift.

## AI Agent Sandboxing & Security

- **System Prompts are NOT Sandboxes**: Instructing a "Plan" agent to "Only use Bash for read-only verification" is fundamentally insecure. If the `Bash` tool is physically provided in the API payload, a hallucinating or helpful LLM *will* eventually use it to execute mutating commands.
- **Hard Sandboxing**: True read-only sandboxing requires strictly omitting the `Bash`, `Edit`, and `Write` tool definitions from the API request.
- **Bash Whitelist Sandbox**: In planning modes where minimal shell access is required, a hardcoded whitelist of safe commands (e.g., `ls`, `git status`) and explicit rejection of chaining/redirection prevents prompt injection.
- **Mathematical Tool Patterns**: Explicitly modeling tool execution with lambda calculus principles (⊗ for parallel execution, ∀ for totality/quotes, Δ for exact idempotent edits, ∞/0 for boundary checks) drastically improves LLM planning reliability.

## Network Resilience & LLM Edge Cases

- **Non-Blocking Exponential Backoff**: Synchronous `(sleep-for ...)` during network retries freezes Emacs. Intercepting the gptel FSM transition to `ERRS` and using `(run-at-time delay ...)` allows for graceful, non-blocking exponential backoff.
- **Auto-Repairing Tool Casing**: LLMs frequently hallucinate tool name casing (e.g., calling `write` instead of `Write`). Intercepting tool execution to perform case-insensitive check and silently correcting prevents pipeline crashes.
- **Handling Hallucinated Tools**: If an LLM hallucinates a tool, keep it in the FSM but immediately inject an error result: `"Error: unknown tool X"`.
- **The `_noop` Proxy Bypass**: If a user disables all active tools but the chat history contains `tool_calls`, dynamically inject a dummy `_noop` tool schema to satisfy validators.

## Emacs Lisp Quirks

- **Batch verification must respect repo-local `var/elpa`**: For verification, either load through the repo's real init path or explicitly bind `minimal-emacs-user-directory`, `user-emacs-directory`, and `package-user-dir`.
- **`vterm-mode-hook` can run before Evil's final state settles**: Pair `evil-set-initial-state` with a next-event-loop correction.
- **Deferred package helpers should `require`, not just `featurep`**: Either the helper itself must `(require 'B nil t)` or local config should advise/wrap to load on demand.
- **Cross-file helper calls need the defining file loaded**: Ensure all required files are loaded before calling functions that aren't autoloaded.
- **Synchronous helper calls need fast non-reasoning models**: For synchronous paths, bind gptel to a fast model like `minimax-m2.5`.
- **Command-generation helpers must validate model output**: Wrap output with a sanitizer that strips formatting and rejects garbage.
- **Dirvish async helpers are sensitive to the spawned Emacs binary**: Pin `dirvish-emacs-bin` to the current `invocation-directory`/`invocation-name`.
- **`gptel--fsm-last` is not always a bare struct**: Normalize first through a coercion helper.
- **Init `load-path` must exist at compile time too**: Wrap local `load-path` setup in `eval-and-compile`.
- **Missing package autoloads are repairable in place**: `package-generate-autoloads` can recreate missing autoload files.
- **`treesit-auto-langs` is an allowlist, not an additive hint**: If JSON highlighting falls back, check whether `json` was omitted.
- **Struct Compilation Warnings**: Wrapping `require` calls in `(eval-when-compile ...)` resolves type warnings.
- **jit-lock Timing Gap with State Flags**: Gate on stable predicates like `(bound-and-true-p gptel-mode)` instead of transient flags.

## Delegation & Context Boundaries

- **Stateless Subagents**: Subagents start fresh without access to parent's context. Parent must bundle all necessary instructions.
- **The Doom Loop of Identical Delegations**: Repeating identical delegation causes subagent to re-execute identical work. Adjust payload on failure rather than blindly repeating.

## API & Network Limitations

- **Progressive Payload Trimming for Retries**: `keep = max(0, default - retries)` escalates aggressively.
- **Tools Array Reduction on Retry**: Filter to only tools referenced in `tool_calls` across all messages.
- **Pre-Send Payload Compaction**: Proactive compaction advises `gptel-curl-get-response` `:before` to estimate JSON size and trim before first send.
- **Moonshot Thinking Fields Must Be Valid Strings**: Normalize every assistant+`tool_calls` reasoning field to a real string.
- **Silent Reasoning Proxy Timeouts**: Force streaming on, or use fast non-reasoning model for subagent tasks.
- **Tool Result Payload Limits**: Truncate massive tool outputs to ~4000 chars, save full output to temp file.
- **Never Use `:stream t` for Subagent Requests**: Non-streaming mode delivers a single complete response, simpler and more reliable.
- **Model-Specific DashScope Failures**: When one model fails with parse errors, try a different model on the same backend.
- **DashScope Requires HTTP/1.1**: Add `:curl-args '("--http1.1")` to backend definition.
- **Empty String Tool Names**: Check for `(or (null name) (eq name :null) (equal name "null") (equal name ""))`.

## Feature Evaluation Discipline

- **"Do We Already Have This?"**: Map features to existing nucleus functionality first.
- **Single Backend Simplicity**: Running one backend eliminates multi-provider auth, error format differences, routing bugs.
- **Server-Side Prompt Caching**: For OpenAI-compatible backends, prompt caching is automatic.

## Tree-sitter Language Patterns

- **ABI Version Pinning**: Emacs 30.2 uses tree-sitter ABI 14. Each grammar needs specific older revision.
- **4-File Pattern for New Languages**: (1) `init-treesit.el` — add to `treesit-auto-langs`, (2) `init-dev.el` — add eglot-ensure hook, (3) `treesit-agent-tools.el` — add fallback regexp, (4) `treesit-agent-tools-workspace.el` — add file extension.
- **Lua Uses Single Node Type**: Lua's tree-sitter grammar uses `function_declaration` for all function definitions.
- **Eglot Batch Mode**: Use `eglot--connect` directly with manual buffer setup and `accept-process-output` waits.

## Emacs Byte-Compilation Traps

- **The `Invalid function` Macro Trap**: Bypass macros using `cl-progv` for dynamic variable binding.
- **Stale `.elc` files cause `void-variable` errors**: `rm -f lisp/*.elc` or add `-*- no-byte-compile: t; -*-` header.
- **Root-level `.elc` files break the init chain**: All init files should have `no-byte-compile` header.
- **Backend integration requires implementing interface functions**: Check git history before implementing.
- **Dead requires for non-existent modules are silent bugs**: Audit all require statements against actual file existence.
- **Test files rot when implementations refactor**: Function renames must propagate to tests.
- **Duplicate definitions silently shadow**: Check for existing definitions before adding customizations.
- **Redundant hooks indicate abstraction opportunity**: Merge hooks with the more flexible interface.
- **Duplicate tool registrations silently overwrite**: Only register tools NOT already defined upstream.

## Upstream Init File Discipline

- **Never modify `init.el` or `early-init.el` directly**: All customizations go in hook files: `pre-early-init.el`, `post-early-init.el`, `pre-init.el`, `post-init.el`.
- **All pre/post init files need `no-byte-compile: t`**: Missing this causes stale `.elc` files.
- **`post-init.el` is the right place for modular config**: Add `lisp/` to `load-path` and `(require 'init-*)` calls here.

## Nucleus Header Convention

- **Canonical engage line**: `engage nucleus: [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA`
- **Collaboration line preserves per-file intent**: `⊗` = parallel execution, `∧` = logical conjunction.
- **Three header formats coexist**: (1) Inline single-line, (2) Multi-line in code blocks, (3) Compact `nucleus:` prefix.

## Symlink Footguns & Data Directory Hygiene

- **`rm -rf symlink/` follows the symlink**: The trailing `/` causes `rm` to resolve the symlink and recurse into target.
- **Root-level symlinks are unnecessary when paths are configured**: Remove them.
- **`.gitignore` allowlist must cover all tracked root files**: Add allowlist entries when tracking new root files.

## Emacs Batch Init Chain

- **`--batch` mode does NOT trigger the full init chain**: Explicitly load `early-init.el` → `package-initialize` → `init.el`.
- **Package reinstall via batch**: Iterate over `package-selected-packages` in batch mode.

## Path Resolution in minimal-emacs.d

- **`minimal-emacs-user-directory`** = repo root (original `user-emacs-directory` before redirect).
- **`user-emacs-directory`** = `var/` (set by `pre-early-init.el`).
- **`package-user-dir`** = `var/elpa` (set by `pre-early-init.el`).
- **`treesit-extra-load-path`** = `var/tree-sitter`.
- **`custom-file`** = repo root `custom.el`.

## Discovery Pattern (λ)

- **Iterative Discovery Loop**: `λ discover(x). ¬plan(x) → concrete(x) → observe(x) → deeper(x) → repeat`
- **Work IS the Insight**: The work itself generates the insight. `each_step_reveals_next`.

## Tool Argument Naming Conventions

- **`file_path` vs `path`**: `file_path` for file operations, `path` for directory operations.
- **Upstream alignment matters**: Match upstream gptel-agent argument names.
- **Breaking changes require coordination**: Update all call sites when renaming.

## Confirmation UI Architecture

- **Two-layer safety net**: Tool confirm (permission) is separate from Preview (review changes).
- **Single source of truth**: `my/gptel-permitted-tools` hash table is the ONLY permit storage.
- **"!" means permit, not bypass**: Add to permits AND apply.

## ECA Bridge Integration Patterns

- **Use internal APIs, don't create new ones**: Check upstream source before assuming functions don't exist.
- **Declare internal variables**: Bridge code that references internal variables needs `defvar`.
- **Guard hash-table access**: `(when (hash-table-p table) (gethash ...))`.
- **Keybinding race conditions**: Both auto-registration and `with-eval-after-load` paths should be idempotent.

## Multi-Project Workspace Patterns

- **Workspace folder ≠ git worktree**: They serve different purposes.
- **Session multiplexing requires explicit selection**: Extensions need session selection commands.
- **Workspace provenance aids AI understanding**: Add `:workspace` property to file context.
- **Cross-session context sharing**: Use `eca--shared-context` for common files.

## Per-Project Subagent Buffer Pattern

- **ALL subagents MUST belong to a project - NO global subagents**: This is enforced; attempting to run a subagent without project context raises an error.
- **Isolate subagent execution per project**: Each project gets dedicated gptel-agent buffer via hash table.
- **Executor overlays persist**: Override `delete-overlay` for executor tasks to maintain visibility.
- **Buffer naming convention**: `*gptel-agent:<project-name>*` for easy identification.
- **4-tier project detection cascade**:
  1. Explicit multi-project mode (`gptel-auto-workflow--current-project`)
  2. Project root override (`gptel-auto-workflow--project-root-override`)
  3. Configured project list (`gptel-auto-workflow-projects`)
  4. Auto-detect from `default-directory`
- **Advice pattern for buffer injection**: Override FSM info and `current-buffer` dynamically; error if no project context found.
- **Overlay cleanup**: Provide explicit cleanup command for persistent executor overlays.

## ai-code-menu Transient Integration

- **Menu-first UX reduces cognitive load**: Add commands to `ai-code-menu` via `transient-append-suffix`.
- **Dynamic status display**: Use functions for `:info` type, not static strings.
- **Conditional menu items**: Hook `transient-setup-hook` to add/remove based on backend.
- **Groups and suffixes cannot be siblings**: Use group name as LOC.
- **Multi-char keys cause errors**: Use single-char keys.

## Auto-Detection Patterns

- **Layer auto-detection behaviors**: Each is independently configurable.
- **Hook ordering matters**: Put workspace hooks early, session creation hooks later.
- **Project root detection cascade**: Try projectile → project.el → fallback.
- **Avoid redundant triggers**: Track last-detected project root.
- **Hook functions need optional argument**: `window-buffer-change-functions` passes frame as argument.

## Upstream Delegation vs Local Extensions

- **Check upstream before implementing**: Re-audit after each upstream update.
- **Slim the bridge**: Remove local copies when upstream provides functions.
- **Alias for discoverability**: Provide `defalias` for common naming variations.
- **Tests verify delegation**: Add tests that check upstream provides expected functions.

## TDD Refactoring Workflow

- **Fix tests before refactoring**: Refactoring with failing tests masks new breakages.
- **P0 > P1 > P2 priority**: Fix critical gaps first.
- **Mock vs integration tests**: Balance mocks for unit tests, real implementations for integration.

## Backend Integration Patterns

- **Don't create parallel infrastructure**: Use existing mechanisms.
- **Use existing session affinity**: Don't create separate hash tables for same purpose.
- **Delegate, don't duplicate**: Use existing functions rather than copying logic.

## Context Window Detection & Auto-Compact

- **`gptel-max-tokens` ≠ context window**: It's response length, NOT context window size.
- **Provider documentation is authoritative**: Research provider docs for context windows.
- **Case-insensitive partial matching**: Match on partial substring for model IDs.
- **Pre-seed popular models**: Don't wait for async API fetch.
- **Auto-compact threshold, not interval**: Primary control is token percentage.
- **Debug command for users**: `M-x my/gptel-context-window-show`.

## Emacs Lisp Pattern Matching (pcase)

- **`pcase` is pattern matching, not just switch**: Destructure, bind variables, test predicates in one expression.
- **Quoted symbols match literally**: `'stopped` matches the symbol `stopped`.
- **Underscore is wildcard**: `_` matches anything.
- **Predicate patterns**: `(pred fn)` tests with predicate.
- **Why use over cond**: Destructuring + matching in one step, compiler checks patterns.

## Context Management Code Organization

- **Facade pattern for config files**: `gptel-config.el` should be a thin facade.
- **Group related functions by domain**: Context-related functionality in `gptel-ext-context.el`.
- **Keybindings live with mode setup**: Bind keys in core/setup modules.
- **Function definition → keybinding separation**: Define functions in feature modules, bind keys elsewhere.

## VSM Architecture Pattern

- **Five-layer separation by purpose**: S5=Identity, S4=Intelligence, S3=Control, S2=Coordination, S1=Operations.
- **Higher layers change less**: S5 principles survive everything else being replaced.
- **Lambda notation for machine-readable rules**: `λ name(x). condition → action | constraint`.
- **Wu Xing elemental mapping**: S5=Water, S4=Fire, S3=Earth, S2=Metal, S1=Wood.
- **Generating cycle (相生)**: Water→Wood→Fire→Earth→Metal→Water.
- **Controlling cycle (相克)**: Wood→Earth→Water→Fire→Metal→Wood.

## Package VC Installation Pitfalls

- **`package-installed-p` returns nil for git clones**: Causes `package-vc-install` to run on every startup.
- **Solution: Just add to load-path**: Skip `package-vc-install` for git-cloned packages.

## gptel/gptel-agent Version Compatibility

- **ELPA lags behind Git main**: Install both from Git main branches.
- **Missing functions break gptel-agent**: `gptel--handle-pre-tool` etc. don't exist in ELPA gptel.

## Per-Preset Model Configuration

- **Different models for different tasks**: Plan mode needs large context; Agent mode needs speed.
- **YAML is single source of truth**: Model is read from YAML frontmatter.
- **Subagent model should differ from parent**: Better tool use with appropriate model.

## Deferred Package Loading for Performance

- **`:demand t` forces immediate load**: Heavy packages load synchronously.
- **`:defer t` with `:commands` for lazy load**: Package loads on first command invocation.
- **Hooks defer to after-init**: Reduces perceived startup time.

## Upstream Directory Structure Compliance

- **Upstream uses `autosave/`, not `auto-save/`**: Match upstream naming.
- **`saveplace` is a file, not directory**: File in `user-emacs-directory`, not subdirectory.
- **Local additions are ok**: `cache/`, `elpa/`, `lockfiles/`, `tmp/`, `savefile/` for local needs.

## Context Window Cache Maintenance

- **Add explicit entries for new models**: Update `my/gptel--known-model-context-windows`.
- **Partial matching can fail**: Explicit entry avoids ambiguity.
- **Model metadata matters too**: Pricing, max output, features belong in metadata.

## LLM-First Decision Making

- **LLM = Brain, We = Eyes + Hands**: LLM decides, we gather context and execute.
- **Never second-guess LLM**: Don't override LLM decisions with local formulas.
- **Fallback only if LLM unavailable**: Local logic is backup, not primary.
- **Rich context = better decisions**: Provide git history, file sizes, TODOs, test results.

## Auto-Workflow Branching

- **Only optimize/* branches pushed**: Never push directly to main.
- **Human reviews before merge**: optimize/* → PR → human review → merge to main.
- **Worktree isolation**: Each experiment in separate worktree to avoid conflicts.
- **Tests before any push**: Must pass tests and nucleus validation.

## Auto-Workflow Autonomy

- **Never ask user**: Retry on failure instead of prompting.
- **Try harder, again and again**: Multiple retry attempts before giving up.
- **Error detection early**: Check for error messages before processing.
- **Log everything**: TSV format for explainable results.

## Eight Keys Signal Phrases

- **Signals in commit messages**: Include phrases like "builds on discoveries", "explicit assumptions".
- **Signals in code comments**: Use ASSUMPTION, BEHAVIOR, TEST, EDGE CASE sections.
- **Scoring looks for phrases**: Eight Keys scoring searches for specific signal patterns.
- **Code quality ≠ Eight Keys**: Good code may still have low Eight Keys without signals.
