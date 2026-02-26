# LEARNING


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
- **Struct Compilation Warnings**: Using `(cl-typep obj 'gptel-openai)` inside advice functions will trigger byte-compiler warnings (`Unknown type gptel-openai`) if the module defining the struct isn't explicitly required. Wrapping the `require` calls in `(eval-when-compile ...)` at the top of the file resolves this without forcing runtime load order issues.