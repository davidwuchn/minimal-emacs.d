# LEARNING

## Table of Contents

- [gptel-agent & Emacs LSP (Eglot) Integration](#gptel-agent--emacs-lsp-eglot-integration)
- [AI Agent Sandboxing & Security](#ai-agent-sandboxing--security)
- [Network Resilience & LLM Edge Cases (OpenCode Style)](#network-resilience--llm-edge-cases-opencode-style)
- [Emacs Lisp Quirks](#emacs-lisp-quirks)
- [Delegation & Context Boundaries](#delegation--context-boundaries)
- [API & Network Limitations (DashScope / OpenAI)](#api--network-limitations-dashscope--openai)
- [Feature Evaluation Discipline](#feature-evaluation-discipline)
- [Subagent Callback Must Handle `(tool-result . ...)`](#subagent-callback-must-handle-tool-result-)
- [Paren Balance in gptel-make-tool Calls](#paren-balance-in-gptel-make-tool-calls)
- [Tree-sitter Language Patterns (Code_* Tools)](#tree-sitter-language-patterns-code_-tools)
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
- [Context Management Code Organization](#context-management-code-organization)
- [VSM Architecture Pattern](#vsm-architecture-pattern)
- [Package VC Installation Pitfalls](#package-vc-installation-pitfalls)
- [gptel/gptel-agent Version Compatibility](#gptelgptel-agent-version-compatibility)
- [Per-Preset Model Configuration](#per-preset-model-configuration)
- [Deferred Package Loading for Performance](#deferred-package-loading-for-performance)
- [Upstream Directory Structure Compliance](#upstream-directory-structure-compliance)
- [Context Window Cache Maintenance](#context-window-cache-maintenance)


## gptel-agent & Emacs LSP (Eglot) Integration
- **Asynchronous JSON-RPC**: Bypassing Emacs interactive UI commands (like `xref-find-definitions`) and querying the LSP server directly via `jsonrpc-async-request` is significantly more efficient and reliable for an AI agent.
- **Server Resolution**: `(eglot-current-server)` can return `nil` if called immediately after `(find-file-noselect ...)` because the server attaches asynchronously. A more robust method is to resolve the project and lookup the server in `eglot--servers-by-project`.
- **Project-Wide Diagnostics**: Iterating over `(buffer-list)` and calling `(flymake-diagnostics)` only yields errors for *open* files. Emacs 29+ provides `(flymake--project-diagnostics)`, which correctly queries the LSP for the entire project's error state, including closed files.
- **0-Indexed vs 1-Indexed**: LSP locations (lines/characters) are 0-indexed, whereas Emacs lines are 1-indexed. Agent tool prompts must explicitly state which indexing system they expect to prevent coordinate drift.

## AI Agent Sandboxing & Security
- **System Prompts are NOT Sandboxes**: Instructing a "Plan" agent to "Only use Bash for read-only verification" is fundamentally insecure. If the `Bash` tool is physically provided in the API payload, a hallucinating or helpful LLM *will* eventually use it to execute mutating commands (like `git commit` or `sed`).
- **Hard Sandboxing**: True read-only sandboxing requires strictly omitting the `Bash`, `Edit`, and `Write` tool definitions from the Emacs Lisp variable (`nucleus--gptel-plan-readonly-tools`) that populates the API request.
- **Bash Whitelist Sandbox**: In planning modes where minimal shell access is required, a hardcoded whitelist of safe commands (e.g., `ls`, `git status`) and explicit rejection of chaining/redirection prevents prompt injection while allowing exploration.
- **Mathematical Tool Patterns**: Explicitly modeling tool execution with lambda calculus principles (e.g., ⊗ for max(t) parallel execution instead of Σ(t) sequential, ∀ for totality/quotes on paths, Δ for exact idempotent string edits, and ∞/0 for boundary/edge case checks) drastically improves LLM planning reliability.

## Network Resilience & LLM Edge Cases (OpenCode Style)
- **Non-Blocking Exponential Backoff**: Synchronous `(sleep-for ...)` during network retries freezes Emacs. Intercepting the gptel FSM transition to `ERRS` and using `(run-at-time delay ...)` allows for graceful, non-blocking exponential backoff when encountering `429 Too Many Requests` or `curl: (28) Timeout`.
- **Auto-Repairing Tool Casing**: LLMs frequently hallucinate tool name casing (e.g., calling `write` instead of `Write`). Intercepting the tool execution loop to perform a `string-equal-ignore-case` check and silently correcting the struct name prevents pipeline crashes and syncs the correction back to the LLM history.
- **Handling Hallucinated Tools**: If an LLM completely hallucinates a tool (e.g., `FileRead`), stripping it from the history causes `400 Bad Request` errors on subsequent Anthropic/LiteLLM turns due to orphaned `tool_calls`. Instead, the tool must be kept in the FSM but immediately injected with an error result: `"Error: unknown tool X"`.
- **The `_noop` Proxy Bypass**: If a user disables all active tools, but the chat history still contains `tool_calls` from previous turns, strict proxies (Anthropic/LiteLLM) will crash. Dynamically injecting a dummy `_noop` tool schema right before JSON serialization satisfies the validator.

## Emacs Lisp Quirks
- **Batch verification must respect repo-local `var/elpa`**: In this repo, ad-hoc `emacs --batch -Q ... (package-initialize)` checks can silently fall back to the default `~/.emacs.d/elpa` and produce bogus install/load failures. For verification, either load through the repo's real init path or explicitly bind `minimal-emacs-user-directory`, `user-emacs-directory`, and `package-user-dir` so package resolution stays inside the workspace `var/elpa`.
- **`vterm-mode-hook` can run before Evil's final state settles**: On first-open terminal buffers, `vterm-mode-hook` may push the buffer to Emacs state and still lose to later Evil or `evil-collection-vterm` initialization that flips `vterm-mode` back to insert. For terminal buffers that must stay in Emacs state, pair the normal `evil-set-initial-state` policy with a next-event-loop `evil-emacs-state` correction so the final state wins after all startup hooks complete.
- **Deferred package helpers should `require`, not just `featurep`**: If a helper function from package A calls into deferred package B and only checks `(featurep 'B)`, the first real use will fail until the user manually loads B. Either the helper itself must `(require 'B nil t)` or local config should advise/wrap the helper to load B on demand before the real call.
- **Cross-file helper calls need the defining file loaded too**: In ai-code, `ai-code-file.el` can call `ai-code-call-gptel-sync`, but that function is defined in `ai-code-prompt-mode.el` and is not autoloaded. If you enable `:`-prefixed shell-command generation from `ai-code-shell-cmd`, you must ensure `ai-code-prompt-mode` is loaded before the first shell-command helper call, otherwise the `:` input is treated like a literal shell command.
- **Colon prompts can bypass helper paths through lower-level runners**: Even after `ai-code-shell-cmd` is fixed, `C-c a !` from a file-visiting buffer may still route through `ai-code-run-current-file` and then `ai-code--run-command-in-comint`, which will try to execute `:prompt` literally. If a high-level command offers both direct execution and AI-generated shell commands, normalize colon-prefixed input at the lowest shared runner too.
- **Synchronous helper calls need fast non-reasoning models**: ai-code's `ai-code-call-gptel-sync` aborts after 30 seconds, so wiring it to the repo's default reasoning-heavy Moonshot model is brittle for helper tasks like shell-command generation or prompt classification. For synchronous helper paths, bind gptel to a fast non-reasoning model/backend pair locally (for example DashScope `qwen3-coder-next`) instead of reusing the main chat default.
- **Command-generation helpers must validate model output, not trust it**: When asking an LLM for a shell command, the model may echo the user's natural-language request or include markdown fences instead of a runnable command. Wrap helper output with a small sanitizer that strips formatting, rejects colon-prefixed echoes like `:list files`, and errors early instead of passing garbage into the shell runner.
- **Dirvish async helpers are sensitive to the spawned Emacs binary**: Dirvish runs directory metadata collection in a separate `-Q -batch` Emacs process using `dirvish-emacs-bin`. If that resolves to a stale or mismatched app-bundle executable, the subprocess can emit truncated Lisp output and Dirvish will report `Fetch dir data failed with error: (end-of-file)`. Pin `dirvish-emacs-bin` to the current `invocation-directory`/`invocation-name` pair so the helper uses the same binary as the running session.
- **`gptel--fsm-last` is not always a bare struct**: In the unreleased FSM build carried by compiled gptel bytecode, inspection and helper paths may encounter wrapped values such as `(FSM . CLEANUP)` or even full request-alist entries `(PROCESS FSM . CLEANUP)`. Any extension code that calls `gptel-fsm-info` or `gptel-fsm-state` on `gptel--fsm-last` or request-alist entries should normalize first through a small coercion helper instead of assuming a raw `gptel-fsm` object.
- **Init `load-path` must exist at compile time too**: If an init module adds local directories like `lisp/modules/` to `load-path` only at runtime, the compiled `.elc` may later fail to resolve private modules even though the source file worked. Wrap local `load-path` setup in `eval-and-compile` so both byte-compilation and runtime agree.
- **Missing package autoloads are repairable in place**: If an ELPA package directory exists but its `*-autoloads.el` file is missing, startup can emit `Error loading autoloads` even though the package sources are present. `package-generate-autoloads` can recreate the missing file in-place, and `package-quickstart-refresh` should be run afterward so quickstart stops pointing at stale autoload state.
- **`treesit-auto-langs` is an allowlist, not an additive hint**: Once you replace the default `treesit-auto-langs` with a custom list, any omitted built-in language recipes stop participating in auto-remap/auto-install. If JSON highlighting mysteriously falls back while other tree-sitter languages work, check whether `json` was accidentally left out of that allowlist.
- **Struct Compilation Warnings**: Using `(cl-typep obj 'gptel-openai)` inside advice functions will trigger byte-compiler warnings (`Unknown type gptel-openai`) if the module defining the struct isn't explicitly required. Wrapping the `require` calls in `(eval-when-compile ...)` at the top of the file resolves this without forcing runtime load order issues.
- **jit-lock Timing Gap with State Flags**: Gating `condition-case` protection on a transient flag (e.g. `my/gptel--streaming-p`) creates a timing gap: when a post-response hook clears the flag then triggers refontification (`jit-lock-refontify`, `font-lock-flush`), the refontification runs *without* protection because the flag is already nil. The fix is to gate on a stable predicate like `(bound-and-true-p gptel-mode)` — the mode stays active for the buffer's lifetime, so protection is unconditional and the timing gap disappears.

## Delegation & Context Boundaries
- **Stateless Subagents**: When an agent delegates a task to a subagent (e.g., via the `Agent` or `RunAgent` tool), the subagent starts fresh without any access to the parent's conversation history or context. The parent agent must explicitly bundle all necessary instructions, constraints, and state into the prompt payload.
- **The Doom Loop of Identical Delegations**: Because subagents are stateless, repeating an identical delegation prompt will cause the subagent to blindly re-execute the exact same work from scratch, yielding the identical result and wasting tokens. If a delegation fails to yield the desired result, the parent agent **must** adjust the payload (e.g., try different search terms, narrow the scope, or explicitly pass the failure context) rather than blindly repeating the identical prompt.

## API & Network Limitations (DashScope / OpenAI)
- **Progressive Payload Trimming for Retries**: Fixed-strategy trimming (always keep N recent tool results) is insufficient — if the initial trim doesn't reduce payload enough, all subsequent retries send the identical oversized payload and fail identically. Progressive trimming (`keep = max(0, default - retries)`) escalates aggressively: retry 1 keeps fewer results, retry 2+ truncates ALL tool results, and `reasoning_content` (chain-of-thought text) is also stripped on retry 2+. The key insight is that `:retries` is already incremented in `info` before the trim function runs, so the function can read it directly.
- **Tools Array Reduction on Retry**: After multiple tool-use rounds, the conversation history reveals which tools the model actually uses (typically 3-5 of 18+ registered). On retry 2+, filtering `:data :tools` to only tools referenced in `tool_calls` across all messages removes 60-80% of tool definitions (~5-8KB JSON overhead). Both the serialized vector (`:data :tools`) and the struct dispatch list (`:tools`) must be filtered in sync. Safety: if no tool_calls exist in messages, skip filtering entirely to avoid sending an empty tools array.
- **Pre-Send Payload Compaction**: Reactive-only trimming (retry after failure) wastes 3 retries + ~14s exponential backoff when the payload is already too large on the first attempt. Proactive compaction advises `gptel-curl-get-response` `:before` to estimate JSON byte size via `gptel--json-encode` and apply the same trimming functions (tool results → reasoning → tools array) in 4 passes before the first send. Key design decisions: (1) only runs when `retries=0` to avoid double-trimming with the retry path, (2) simulates `:retries` values temporarily to reuse existing trim functions then resets to 0, (3) uses both a global byte limit and per-model limits (the minimum wins), (4) byte-level thresholds (~3.5 bytes/token heuristic) are simpler and more accurate than token counting for HTTP payload limits.
- **Moonshot Thinking Fields Must Be Valid Strings, Not Just Present**: For Moonshot/Kimi tool-calling, repairing only *missing* `reasoning_content` fields is insufficient. After compaction or history replay, assistant tool-call messages may still carry invalid null-like sentinels such as Elisp `nil` or `:null`, and Moonshot rejects those with the same 400-class validation failure as a missing field. Normalize every assistant+`tool_calls` reasoning field to a real string (`stored reasoning` or `""`) before serialization.
- **Silent Reasoning Proxy Timeouts**: When a subagent invokes tools, streaming is often disabled. If the subagent uses a reasoning model (like `qwen3.5-plus`), it will generate "thinking" tokens silently in the background for 30+ seconds. Aggressive proxies like DashScope will assume the connection is dead and drop the TCP connection, resulting in a cryptic `Could not parse HTTP response` or `Empty reply from server` error. The fix is to either force streaming on, or use a fast non-reasoning model (like `qwen3-coder-next`) for subagent tasks to ensure the API responds before the proxy timeout.
- **Tool Result Payload Limits**: DashScope and OpenAI enforce strict limits on the size of tool execution results returned in a single HTTP request (typically ~30KB-50KB). If a subagent reads a massive file and returns the entire file contents as its `RunAgent` tool output, the parent agent's subsequent request will instantly fail with a 400/500 error. The solution is to strictly truncate massive tool outputs (e.g. to 4000 chars), save the full output to a local disk temp file, and append a note to the LLM (e.g., `[Result truncated. Full result saved to /tmp/file.txt]`).
- **Never Use `:stream t` for Subagent Requests**: The upstream `gptel-agent--task` uses non-streaming mode deliberately. Adding `:stream t` to subagent `gptel-request` calls causes multiple failures: (1) DashScope/OpenAI-compatible proxies may return unparseable chunked responses, (2) the streaming callback receives multi-phase events (`stringp` chunks, `t` end-of-stream, `nil` error) that interact badly with the FSM's TOOL→WAIT→TOOL cycle, and (3) the `(eq resp t)` end-of-stream signal races with `:tool-use` flag checks. Non-streaming mode delivers a single complete response string, which is both simpler and more reliable.
- **Model-Specific DashScope Failures**: Not all models on a DashScope proxy respond identically. `glm-4.7` produced `"Could not parse HTTP response"` errors even in non-streaming mode (HTTP 200 but `gptel--parse-response` returned nil), while `qwen3-coder-next` on the same endpoint worked perfectly. When a subagent fails with parse errors on one model, try a different model on the same backend before debugging the HTTP layer.

## Feature Evaluation Discipline
- **"Do We Already Have This?"**: Before implementing a feature seen in another tool (OpenCode, Cursor, Roo Code), map it to existing nucleus functionality first. Most "missing features" are already present under different names: @-mentions = gptel-context + tool-calling, three-layer defense = retry + compaction, per-mode routing = nucleus-presets with buffer-local backend/model.
- **Single Backend Simplicity**: Running one backend (Moonshot/K2.5) for all modes eliminates an entire class of problems — multi-provider auth management, per-provider error format differences, routing logic bugs, and doubled debugging surface area. Only split to multiple providers when a single model demonstrably fails at a specific task category.
- **Server-Side Prompt Caching**: For OpenAI-compatible backends (DashScope, Moonshot, DeepSeek), prompt caching is automatic and server-side — stable system prompts get cached without any client-side `cacheControl` headers. Anthropic's explicit cache headers are irrelevant unless using Anthropic directly.

## Subagent Callback Must Handle `(tool-result . ...)`
- When a subagent uses tools internally, the callback receives `(tool-result . result-alist)` events from `gptel--handle-tool-use` after tools complete (line 1717-1718 of gptel-request.el). Upstream's `gptel-agent--task` silently drops these (pcase fallthrough). Custom overrides must also handle/ignore them — logging them with large payloads will crash the `*Messages*` buffer.

## Paren Balance in gptel-make-tool Calls
- **Deep Lambda Bodies Eat Keyword Args**: When a `gptel-make-tool` call contains a deeply nested lambda (condition-case → with-timeout → with-current-buffer → if/let chains), a single missing `)` at the end of the lambda body causes `:args`, `:category`, `:confirm`, and `:include` keyword arguments to be parsed as part of the lambda body instead of being passed to `gptel-make-tool`. The tool registers with `nil` for all metadata (wrong category, no confirmation for destructive ops, results not included in buffer). Forward-sexp from each lambda's `(` is the reliable way to verify the boundary falls right before `:args`.
- **Ripgrep Respects .gitignore `*` Pattern**: A `.gitignore` starting with `*` (ignore everything, selectively un-ignore with `!`) causes ripgrep's default gitignore parsing to ignore project files. Any `call-process "rg"` invocation in the config must use `--no-ignore` plus explicit `--glob "!*.elc" --glob "!var/elpa/"` to exclude unwanted files manually.
- **Batch Mode Needs Explicit Tree-sitter Parsers**: `find-file-noselect` in batch Emacs opens `.el` files in `emacs-lisp-mode`, not `emacs-lisp-ts-mode`, so no tree-sitter parser is created. Any tool that relies on `treesit-parser-list` must call an ensure-parser function that creates a parser based on file extension when none exists.

## Tree-sitter Language Patterns (Code_* Tools)
- **ABI Version Pinning**: Emacs 30.2 uses tree-sitter ABI 14. Latest grammars often compile to ABI 15 and fail with `version-mismatch`. Each grammar needs a specific older revision: Python `v0.21.0`, Rust `v0.21.0`, Elisp `1.2`, C `v0.21.4`, C++ `v0.22.3`, Lua `v0.2.0`, Java/Clojure `master` (works as-is).
- **4-File Pattern for New Languages**: Adding a language requires exactly 4 changes: (1) `init-treesit.el` — add to `treesit-auto-langs` + recipe with ABI14 revision, (2) `init-dev.el` — add eglot-ensure hook, (3) `treesit-agent-tools.el` — add fallback regexp in `get-defun-regexp`, (4) `treesit-agent-tools-workspace.el` — add file extension to `ensure-parser`.
- **Lua Uses Single Node Type**: Lua's tree-sitter grammar uses `function_declaration` for ALL function definitions (local, module, method-style, global). The `name` field contains the full qualified name (`helper`, `M.calculate`, `M:init`), so no custom name extraction fallback is needed.
- **Eglot Batch Mode**: `eglot-ensure` doesn't work in batch (async hooks don't fire). Must use `eglot--connect` directly with manual buffer/language setup and `accept-process-output` waits.

## Emacs Byte-Compilation Traps
- **The `Invalid function` Macro Trap**: If a macro (like `gptel-with-preset`) is not loaded into the environment *before* an Elisp file is byte-compiled, Emacs assumes it is a regular function and compiles it as such. At runtime, when the macro is actually loaded, executing the compiled code throws `Invalid function: gptel-with-preset` because it expects a compiled function but finds a macro. The safest fix is completely bypassing the macro by dynamically binding the variables using `cl-progv` (e.g., `(cl-progv syms vals ...)`), ensuring the code behaves predictably whether byte-compiled or evaluated dynamically.
- **Stale `.elc` files cause `void-variable` errors**: When a source `.el` file defines a variable/function but the compiled `.elc` file is outdated (from a previous version), Emacs may load the stale `.elc` and encounter references to variables that no longer exist or have different names. The error message `(void-variable my-evil-comment-or-uncomment)` doesn't point to the real cause — a stale `.elc` in `lisp/`. Solution: `rm -f lisp/*.elc` or add `-*- no-byte-compile: t; -*-` header to prevent compilation.
- **Root-level `.elc` files break the init chain**: Stale compiled files at repo root (`early-init.elc`, `init.elc`) are especially insidious — they can cause `minimal-emacs--check-success` to fail with "Configuration error" because the init chain silently aborts mid-way. Fix: all `lisp/*.el` and `lisp/modules/*.el` files now have `-*- no-byte-compile: t; -*-` header to prevent compilation entirely.
- **Backend integration requires implementing interface functions**: When adding a backend to `ai-code-backends.el`, all specified functions (`:send`, `:resume`, `:upgrade`, `:install-skills`) must be defined. Missing functions cause silent failures. For non-CLI backends like ECA, implement wrappers around the native API (e.g., `ai-code-eca-send` wraps `eca-chat-send-prompt`). Check git history before implementing new — functions may have been removed as "dead code" but are actually needed for the backend interface.
- **Git history as source of truth**: When re-implementing removed functions, check git history (`git log -p -S "function-name" -- file.el`) for the original implementation. The original author's intent is preserved in the diff. For `ai-code-eca-send`, the original opened the chat buffer before sending — a detail my reimplementation initially missed.
- **Dead requires for non-existent modules are silent bugs**: `(require 'module nil t)` with a non-existent module silently succeeds but may hide missing functionality. After file merges or refactors, audit all require statements against actual file existence. Duplicate require blocks (from merged files) are a code smell — consolidate into one block at file top.
- **Test files rot when implementations refactor**: Function renames (`menu-suffixes` → `menu-group`) must propagate to tests. CI catches this, but local batch testing requires the full dependency chain (`magit`, `eca`, etc.). Keep tests minimal and mock heavy dependencies where possible.
- **Duplicate definitions silently shadow**: A `defvar` followed by a `defcustom` with the same name causes silent shadowing. The `defvar` becomes dead code. When adding customizations, check for existing definitions with `grep -n "defvar\|defcustom" file.el`.
- **Redundant hooks indicate abstraction opportunity**: When two hooks do nearly the same thing (`auto-add-workspace` vs `auto-sync-workspace`), the difference is usually trigger frequency or a prompt option. Merge into one with the more flexible interface (prompt vs auto).
- **Duplicate tool registrations silently overwrite**: When `gptel-tools-register-all` registers a tool with the same name as one in `gptel-agent-tools.el`, it silently overwrites with the newer (possibly worse) definition. The fix: only register tools that are NOT already defined upstream. Check with `grep ':name "ToolName"' var/elpa/gptel-agent-*/gptel-agent-tools.el` before adding inline definitions. Missing argument `:description` fields can cause LLM validation failures.

## Upstream Init File Discipline
- **Never modify `init.el` or `early-init.el` directly**: These are upstream-managed files from `jamescherti/minimal-emacs.d`. All customizations go in the 4 hook files: `pre-early-init.el`, `post-early-init.el`, `pre-init.el`, `post-init.el`. This allows clean `git pull` from upstream without merge conflicts.
- **All pre/post init files need `no-byte-compile: t`**: The upstream README mandates that all 4 hook files include `;;; FILENAME.el --- DESCRIPTION -*- no-byte-compile: t; lexical-binding: t; -*-` as the first line. Missing this causes compile-angel or `byte-compile-file` to produce `.elc` files that may load stale code.
- **Upstream now supports selectively skipping hook stages**: `early-init.el` defines `minimal-emacs-load-pre-early-init`, `minimal-emacs-load-post-early-init`, `minimal-emacs-load-pre-init`, and `minimal-emacs-load-post-init`. In practice, `pre-early-init.el` is the right place to disable the later three stages temporarily when bisecting startup problems, while `minimal-emacs-load-pre-early-init` itself can only be useful if set before `early-init.el` starts.
- **`post-init.el` is the right place for modular config**: Add `lisp/` to `load-path` and `(require 'init-*)` calls in `post-init.el` (loaded after `init.el`). Do NOT add load-path manipulation to `init.el` itself.
- **Extracting upstream settings into separate files is unnecessary**: Upstream `init.el` already contains comprehensive defaults (scrolling, dired, eglot, ediff, etc.). Extracting them into a separate `init-defaults.el` creates a maintenance burden — the settings are duplicated, and upstream updates require manual diffing. Just let `init.el` carry its own defaults and override specific values in `post-init.el` if needed.

## Nucleus Header Convention
- **Canonical engage line**: `engage nucleus: [phi fractal euler tao pi mu ∃ ∀] | [Δ λ Ω ∞/0 | ε/φ Σ/μ c/h] | OODA` — this is the single source of truth for the symbolic framework header. Uses spelled-out `phi` (not `φ`), includes existential/universal quantifiers `∃ ∀`, and the totality symbol `Ω`.
- **Collaboration line preserves per-file intent**: The second line (`Human ⊗ AI`, `Human ⊗ AI ⊗ REPL`, `Human ∧ AI`) is NOT uniform — each file's operator reflects its semantic intent. `⊗` = tensor product (parallel execution), `∧` = logical conjunction (nucleus-tutor enforces strict AND). `⊗ REPL` suffix only appears in files where REPL interaction is integral (e.g. clojure-expert, reference docs). Do not blindly unify this line.
- **Three header formats coexist**: (1) Inline single-line in agents/prompts: `engage nucleus: [...] | OODA` + `Human ⊗ AI`. (2) Multi-line in code blocks in skills: three separate lines inside triple-backtick fences. (3) Compact `nucleus:` prefix in utility prompts (inline_completion, rewrite, title, compact) — these do NOT use the engage header at all.
- **`.gitignore` deny-all pattern**: The repo uses `*` at top of `.gitignore`. All files under `assistant/` and `lisp/modules/` require `git add -f` to stage. `rg` (ripgrep) also respects `.gitignore` by default — use `--no-ignore` when searching these directories.

## Symlink Footguns & Data Directory Hygiene
- **`rm -rf symlink/` follows the symlink**: On macOS/Linux, `rm -rf elpa/` where `elpa` is a symlink to `var/elpa` will **delete the contents of `var/elpa/`**, not the symlink itself. The trailing `/` (or shell tab-completion adding it) causes `rm` to resolve the symlink and recurse into the target. The safe way to remove a symlink is `rm elpa` (no trailing slash, no `-rf`).
- **Root-level symlinks are unnecessary when paths are configured**: If `package-user-dir` points to `var/elpa` and `treesit-extra-load-path` includes `var/tree-sitter`, no root-level `elpa/` or `tree-sitter/` symlinks are needed. They only create confusion and symlink footgun risk. Remove them.
- **`.gitignore` allowlist must cover all tracked root files**: The deny-all `*` pattern means every tracked file at the repo root needs an explicit `!filename` entry. `pre-early-init.el` and `post-early-init.el` were tracked (via `git add -f`) but not allowlisted — this causes `git status` to show them as ignored in fresh clones. Always add allowlist entries when tracking new root files.

## Emacs Batch Init Chain
- **`--batch` mode does NOT trigger the full init chain**: Running `emacs --batch --init-directory=DIR` does not automatically load `early-init.el` → `init.el`. For full verification of the init chain in batch mode, you must explicitly: (1) `--load early-init.el`, (2) call `(package-initialize)`, (3) `--load init.el`. This is the only reliable way to test that all packages load correctly without launching a GUI.
- **Package reinstall via batch `package-install`**: After catastrophic loss of `var/elpa/`, all packages can be reinstalled by iterating over `package-selected-packages` in batch mode: `emacs --batch -l early-init.el --eval '(package-initialize)' --eval '(package-refresh-contents)' --eval '(mapc #'\''package-install package-selected-packages)'`. The `eca` package (installed via `:vc`) needs a separate `package-vc-install` call.

## Path Resolution in minimal-emacs.d
- **`minimal-emacs-user-directory`** = repo root (`~/.emacs.d/` = `~/workspace/minimal-emacs.d/`). This is the *original* `user-emacs-directory` before `pre-early-init.el` redirects it.
- **`user-emacs-directory`** = `var/` (set by `pre-early-init.el`). All Emacs-generated data goes here.
- **`package-user-dir`** = `var/elpa` (set by `pre-early-init.el`). ELPA packages install here.
- **`treesit-extra-load-path`** = `var/tree-sitter` (set in `post-init.el` via `(expand-file-name "tree-sitter" user-emacs-directory)` — by this point `user-emacs-directory` is already `var/`).
- **`custom-file`** = repo root `custom.el` (uses `minimal-emacs-user-directory`). This stays at root because it's version-controlled.

## Discovery Pattern (λ)
- **Iterative Discovery Loop**: `λ discover(x). ¬plan(x) → concrete(x) → observe(x) → deeper(x) → repeat` — when exploring the unknown, don't start with a plan. Make it concrete, observe what happens, go deeper, repeat. Each step reveals the next step.
- **Work IS the Insight**: The work itself generates the insight. You don't pre-plan the answer; the answer emerges through the act of working. `each_step_reveals_next`.

## Tool Argument Naming Conventions
- **`file_path` vs `path`**: Establish clear convention early. `file_path` for file operations (Read, Edit, Insert), `path` for directory operations (Write, Glob, Grep). LLMs hallucinate less when conventions are consistent.
- **Upstream alignment matters**: Match upstream gptel-agent tool argument names. Divergent naming (`path` vs `file_path`) causes LLM confusion and user friction.
- **Breaking changes require coordination**: When renaming arguments, update all call sites: tool definitions, benchmark mocks, example prompts.

## Confirmation UI Architecture
- **Two-layer safety net**: Tool confirm (permission to execute) is separate from Preview (review changes before applying). Permits control the first layer, preview settings control the second. Never bypass preview based on permits — preview is the final safety check for mutating operations.
- **Single source of truth**: `my/gptel-permitted-tools` hash table is the ONLY permit storage. Avoid multiple permit-like flags (e.g., `never-ask-again`) that create confusion.
- **"!" means permit, not bypass**: When user types "!" in preview, add the tool to permits AND apply. This teaches the system for future calls while still applying the current change.

## ECA Bridge Integration Patterns
- **Use internal APIs, don't create new ones**: `eca--session-add-workspace-folder` exists in `eca-util.el`. Don't invent `eca-ext-add-workspace-folder`. Check upstream source before assuming functions don't exist.
- **Declare internal variables**: ECA's `eca--sessions` is a hash table, not exported. Bridge code that references it needs `defvar` with documentation noting it's internal.
- **Guard hash-table access**: `(gethash key table)` errors if `table` isn't a hash table. Always `(when (hash-table-p table) (gethash ...))` for safety.
- **Keybinding race conditions**: If setting up keybindings in `with-eval-after-load`, call the setup function from auto-registration too. Both paths may execute; both should be idempotent.

## Multi-Project Workspace Patterns
- **Workspace folder ≠ git worktree**: A workspace folder is a project directory added to an ECA session for AI context. A git worktree is a separate checkout of the same repo. They serve different purposes: workspace folders give AI context across projects; worktrees let you work on multiple branches simultaneously.
- **Session multiplexing requires explicit selection**: ECA's `eca-session` returns the session for the current buffer's root. With multiple sessions, `eca--session-id-cache` tracks the "current" one. Extensions need `eca-list-sessions`, `eca-switch-to-session` for user control.
- **Workspace provenance aids AI understanding**: Adding `:workspace` property to file context (`:workspace "/project" :relative-path "src/file.el"`) helps AI understand which project each file belongs to when working across multiple repositories.
- **Cross-session context sharing**: Shared context (`eca--shared-context`) allows common files/repo-maps to be applied to all sessions. Useful for shared libraries, documentation, or dependency knowledge that should be available regardless of active project.

## ai-code-menu Transient Integration
- **Menu-first UX reduces cognitive load**: Users shouldn't need to memorize `C-c e` prefix. Adding ECA commands to `ai-code-menu` via `transient-append-suffix` makes them discoverable when ECA backend is selected.
- **Dynamic status display**: `:info` type in transient groups can display dynamic values (session ID, folder count). Use functions (`ai-code-eca--session-status-description`) not static strings.
- **Conditional menu items**: Hook `transient-setup-hook` to add/remove menu items based on `ai-code-selected-backend`. Items appear only when relevant backend is active.
- **Group organization**: 4 groups for ECA: Workspace (w prefix), Context (c prefix), Shared Context, Sessions (s prefix). Mnemonics reduce memorization.
- **Backend-specific suffixes require tracking**: Use a flag (`ai-code-eca--menu-suffixes-added`) to prevent duplicate additions. `transient-remove-suffix` on unload or backend switch.
- **transient-append-suffix uses string, not list**: The LOC argument is a string like `"s"`, NOT a list like `'("s")`. List format causes silent errors in `condition-case nil` blocks. Always check transient documentation for argument types.
- **Log errors in condition-case**: When using `condition-case`, bind the error variable (`(condition-case err ... (error (message "...: %s" err)))`) to see what went wrong. Silent `nil` swallows bugs.
- **Groups and suffixes cannot be siblings**: In transient, a group `["Group Name" ...]` cannot be inserted as sibling of a suffix `("k" "description" command)`. Use group name as LOC: `(transient-append-suffix 'prefix "Existing Group" ["New Group" ...])`. The LOC must match the level where you're inserting.
- **LOC is a key/command string, not a group name**: The LOC argument for `transient-append-suffix` must be a key like `"N"` (the last item in a group), NOT a group name like `"Other Tools"`. To append a group after another group, use the key of the last suffix in that group.
- **Multi-char keys cause errors**: Transient suffix keys like `("wr" ...)` cause `Wrong type argument: number-or-marker-p, "wr"` error. Use single-char keys: `("r" ...)`. Multi-char sequences only work with prefix keys, not in suffix vectors.
- **Coordinate lists for top-level insertion**: `nil` as LOC doesn't work for `transient-append-suffix`. Use coordinate list `'(0 -1)` to append at end of top-level vector. Format: `(level index)` where `-1` means last position.
- **Show session id, not raw struct**: Functions like `ai-code-eca-which-session` should display `(message "ECA session %d: %s" id folders)` not `(message "Current ECA session: %s" session)`. Raw struct output is unreadable.
- **ECA's C-c . menu is separate**: ECA has its own transient menu (`eca--transient-menu-prefix`) for chat operations. Don't modify it — use `ai-code-menu` for workspace/context integration.

## Auto-Detection Patterns
- **Layer auto-detection behaviors**: (1) `eca-auto-add-workspace-folder` - add project on file open, (2) `eca-auto-switch-session` - switch to matching session, (3) `eca-auto-create-session` - create session for new projects, (4) `eca-auto-sync-workspace` - keep workspace in sync. Each is independently configurable.
- **Hook ordering matters**: `find-file-hook` runs hooks in order. Put `eca--auto-add-workspace-hook` early (default priority) and `eca--auto-create-session-hook` later (90 priority) so workspace addition happens before session creation check.
- **Project root detection cascade**: Try `projectile-project-root` first, then `project-root` (project.el), then `file-name-directory` as fallback. Each may return nil.
- **Avoid redundant triggers**: Track last-detected project root (`eca--last-project-root`) to skip hooks when switching between files in the same project. Prevents flicker.
- **Auto-switch needs session lookup**: `eca--session-for-project-root` iterates sessions to find one whose workspace contains the project. O(n) but sessions are few.
- **Backend auto-switch**: When ECA session activates, `ai-code-selected-backend` should auto-set to `'eca`. Use advice on `eca-switch-to-session` for this. Prevents requests going to wrong backend.
- **Hook functions need optional argument**: `window-buffer-change-functions` passes the frame as argument. Hook functions must accept `(&optional _frame)` to avoid `wrong-number-of-arguments` errors. The frame argument is often not needed but must be declared.

## Upstream Delegation vs Local Extensions
- **Check upstream before implementing**: ECA upstream gained `eca-chat-add-workspace-root`, `eca--session-for-worktree`, automatic worktree detection. Local implementations became redundant. Re-audit after each upstream update.
- **Slim the bridge**: If upstream provides core functions, remove local copies. Bridge should only provide what upstream lacks. Lines saved = maintenance burden reduced.
- **Alias for discoverability**: Users may search for `eca-chat-add-workspace-folder` but actual function is `eca-add-workspace-folder`. Provide `defalias` for common naming variations.
- **Session feedback improves UX**: When adding workspace folder, show session ID in message (`"Added to session %d: %s"`). Multi-session workflows need clarity about which session was affected.
- **Tests verify delegation**: Add tests that check upstream provides expected functions (`string-match-p "defun eca-chat-add-workspace-root" source`). Catches drift when upstream changes.

## TDD Refactoring Workflow
- **Fix tests before refactoring**: When tests fail in batch but pass in isolation, fix them first. Refactoring with failing tests masks new breakages.
- **P0 > P1 > P2 priority**: Fix critical gaps first. High-risk untested code is a bomb waiting to go off.
- **Mock vs integration tests**: Mocks are fast but don't catch real bugs. Balance: mock for unit tests, real implementations for integration tests.
- **Test pollution exists**: Some tests pass in isolation but fail when loaded together. Isolate and fix, or document known limitation.

## Backend Integration Patterns
- **Don't create parallel infrastructure**: If integrating with a system (like ai-code), use its existing mechanisms. ECA integrates via `ai-code-select-backend`, not a separate menu. Dead code claiming "menu integration" is misleading.
- **Use existing session affinity**: `ai-code--repo-backend-alist` already tracks preferred backend per repo. Don't create a separate hash table for the same purpose.
- **Delegate, don't duplicate**: If `ai-code-git-worktree-branch` exists, use it. Don't copy its logic into the bridge.
- **Aspirational vs actual**: STATE.md should document what IS, not what could be. Claiming "menu integration" when menu items are never displayed is documentation debt.

## Context Window Detection & Auto-Compact
- **`gptel-max-tokens` ≠ context window**: `gptel-max-tokens` is response length, NOT context window size. Using it as fallback causes auto-compact to trigger at 8k tokens instead of 128k+. Never include it in context window fallback chain.
- **Provider documentation is authoritative**: Model context windows vary wildly (8k → 1M tokens). Don't assume defaults. Research provider docs: Qwen3.5-Plus = 1M, DeepSeek V3 = 163k, MiniMax M2.5 = 196k. OpenRouter model pages show context length.
- **Case-insensitive partial matching**: Model IDs vary (`qwen3.5-plus`, `openai/gpt-4o`, `qwen-plus-2025-12-01`). Match on partial substring to handle version suffixes and provider prefixes.
- **Pre-seed popular models**: Don't wait for async API fetch. Seed `my/gptel--known-model-context-windows` with correct values for models you use. Async fetch is unreliable (no API key, network issues).
- **Auto-compact threshold, not interval**: Primary control should be token percentage (80% of context window), not elapsed time. Interval is a secondary safeguard against rapid re-compact cycles.
- **Debug command for users**: `M-x my/gptel-context-window-show` shows model, context window, threshold, current usage. Essential for diagnosing "why is it compacting?" questions.

## Emacs Lisp Pattern Matching (pcase)
- **`pcase` is pattern matching, not just switch**: Like a powerful `case`/`switch` that can destructure, bind variables, and test predicates in one expression.
- **Basic syntax**: `(pcase EXPR (PATTERN BODY...) ...)` — evaluates EXPR, matches against PATTERNs in order, executes first matching BODY.
- **Quoted symbols match literally**: `'stopped` matches the symbol `stopped`. Use backquote for lists: `` `(a ,b) `` matches `(a anything)` and binds `b`.
- **Underscore is wildcard**: `_` matches anything. Use as default case.
- **Binding variables in patterns**: `` `(,x ,y ,z) `` matches a 3-element list and binds `x`, `y`, `z` to elements. Variables without comma are pattern literals.
- **Predicate patterns**: `(pred fn)` tests with predicate. `(pred stringp)` matches strings. Combine with variable: `(and (pred numberp) n)` binds `n` if number.
- **Destructuring structs/lists**: `(app fn pat)` applies function then matches. `(app car 'stopped)` extracts car then matches.
- **Why use over cond**: (1) Destructuring + matching in one step, (2) Compiler checks patterns, (3) More readable for complex data, (4) Functional style without nested if/let.
- **Example from ECA integration**:
  ```elisp
(pcase (eca--session-status session)
     ('stopped  (eca-process-start session ...))
     ('started  (eca-chat-open session))
     ('starting (eca-info "already starting")))
   ```

## Context Management Code Organization
- **Facade pattern for config files**: `gptel-config.el` should be a thin facade that only requires modules. Interactive commands and helpers belong in feature-specific modules like `gptel-ext-context.el`.
- **Group related functions by domain**: `gptel-ext-context.el` houses all context-related functionality: auto-compaction, context window detection, token estimation, and interactive context commands like `my/gptel-add-project-files`.
- **Keybindings live with mode setup**: The `C-c C-p` binding for `my/gptel-add-project-files` lives in `gptel-ext-core.el` alongside other gptel-mode-map bindings, not in the function definition file.
- **Function definition → keybinding separation**: Define functions in feature modules, bind keys in core/setup modules. This allows the feature to be loaded independently of keybinding preferences.

## VSM Architecture Pattern
- **Five-layer separation by purpose**: VSM (Viable System Model) separates concerns by *why they exist*, not by feature. S5=Identity (what the system IS), S4=Intelligence (how it adapts), S3=Control (resource management), S2=Coordination (how parts work together), S1=Operations (what it does).
- **Higher layers change less**: S5 principles survive everything else being replaced. S1 tools change most often. When S5 changes, everything below shifts.
- **Lambda notation for machine-readable rules**: Encode principles as `λ name(x). condition → action | constraint`. Symbols: `→` (implies), `|` (also), `>` (preferred over), `∧` (and), `∨` (or), `¬` (not), `≡` (defined as).
- **Wu Xing elemental mapping**: S5=Water (deep soul), S4=Fire (illuminates unknown), S3=Earth (grounding foundation), S2=Metal (prunes chaos), S1=Wood (living core). Use for diagnostics: symptom → element imbalance → remedy.
- **Generating cycle (相生)**: Water→Wood→Fire→Earth→Metal→Water. Each layer enables the next.
- **Controlling cycle (相克)**: Wood→Earth→Water→Fire→Metal→Wood. Each layer constrains another.
- **Diagnostic use**: Chaos/burnout = Wood excess (S1 without S2). No innovation = Fire deficient (S4 weakness). Bureaucracy kills ideas = Metal excess (S2 strangling S1).
- **Flat principles are a smell**: Treating "use PostgreSQL" and "never suppress errors" as equally important is wrong. One is S1 (tool choice), the other is S5 (identity principle).

## Package VC Installation Pitfalls
- **`package-installed-p` returns nil for git clones**: A package cloned with `git clone` to `var/elpa/gptel/` is NOT recognized by `package-installed-p`. This causes `package-vc-install` to run on every startup, hanging Emacs.
- **Solution: Just add to load-path**: For git-cloned packages, skip `package-vc-install` entirely and just add the directory to `load-path`:
  ```elisp
  (let ((elpa-dir (expand-file-name "var/elpa" minimal-emacs-user-directory)))
    (add-to-list 'load-path (expand-file-name "gptel" elpa-dir))
    (add-to-list 'load-path (expand-file-name "gptel-agent" elpa-dir)))
  ```
- **Pre-commit hook needs local packages**: CI/pre-commit scripts must either install packages or assume they exist. Use a `scripts/setup-packages.sh` that clones required packages, called by the pre-commit hook.

## gptel/gptel-agent Version Compatibility
- **ELPA lags behind Git main**: ELPA's `gptel-0.9.9.4` is 44+ commits behind `karthink/gptel` main branch.
- **Missing functions break gptel-agent**: `gptel-agent` (20260308) expects `gptel--handle-pre-tool`, `gptel--handle-post-tool`, `gptel--handle-tool-result` which don't exist in ELPA gptel.
- **Error: Symbol's function definition is void**: This error on `gptel--handle-pre-tool` means you need newer gptel.
- **Fix**: Install both `gptel` and `gptel-agent` from Git main branches, not ELPA.

## Per-Preset Model Configuration
- **Different models for different tasks**: Plan mode (research) needs large context; Agent mode (execution) needs speed; Subagents need reliability.
- **Use `defcustom` for preset models**:
  ```elisp
  (defcustom nucleus-plan-model 'qwen3.5-plus
    "Model for gptel-plan preset (read-only planning)."
    :type 'symbol
    :group 'nucleus-presets)
  ```
- **Override in preset definition**: Pass the custom variable to `gptel-make-preset` instead of hardcoded model symbol.
- **Subagent model should differ from parent**: `minimax-m2.5` (196k context, 80.2% SWE-Bench) is better for subagent tool use than parent buffer's model.

## Deferred Package Loading for Performance
- **`:demand t` forces immediate load**: Heavy packages like `ai-code` load synchronously at startup.
- **`:defer t` with `:commands` for lazy load**: Package loads on first command invocation:
  ```elisp
  (use-package ai-code
    :ensure nil
    :defer t
    :commands (ai-code-menu ai-code-set-backend)
    :bind ("C-c a" . ai-code-menu))
  ```
- **Hooks defer to after-init**: `:hook (after-init . mode)` runs after startup completes, reducing perceived startup time.
- **ai-code is heavy**: Deferring it saves ~200-500ms startup time.

## Upstream Directory Structure Compliance
- **Upstream uses `autosave/`, not `auto-save/`**: `auto-save-list-file-prefix` points to `autosave/` directory.
- **`saveplace` is a file, not directory**: Upstream puts `saveplace` file directly in `user-emacs-directory`, not in a subdirectory.
- **`abbrev_defs` is a file**: Same pattern — file in `var/`, not subdirectory.
- **Why follow upstream**: Reduces cognitive load when debugging, matches expectations from upstream docs, avoids "why are there two autosave directories?" confusion.
- **Local additions are ok**: `cache/`, `elpa/`, `lockfiles/`, `tmp/`, `savefile/` for local needs, but don't rename upstream directories.

## Context Window Cache Maintenance
- **Add explicit entries for new models**: When adding a model, update `my/gptel--known-model-context-windows` with exact name:
  ```elisp
  ("qwen3-coder-next" . 131072)
  ("kimi-k2.5" . 262144)
  ```
- **Partial matching can fail**: A model `qwen3-coder-next` might match `qwen3-coder` prefix, but explicit entry is clearer and avoids ambiguity.
- **Model metadata matters too**: Pricing, max output, features (vision/tools), description belong in `my/gptel--known-model-metadata`.
- **Research pricing from provider docs**: OpenRouter shows pricing; DashScope docs show Qwen pricing; provider pages are authoritative.
