# PLAN: Programmatic Tool Calling (v0.6.0)

## Status: ✓ MOSTLY IMPLEMENTED

## Goal

Add a new `Programmatic` tool that lets the execution agent write a small,
restricted Emacs Lisp program which orchestrates multiple existing tools inside
one tool call. The purpose is to reduce round trips and token usage for
multi-step workflows without creating a second unrestricted execution surface.

## Why This Exists

### Current Problem

- Multi-tool workflows pay one LLM round trip per tool call
- Tool-call/result chatter bloats the context window
- Repetitive search-orchestrate-summarize tasks are slower than necessary

### Desired Outcome

- Batch read-only and mixed-tool workflows into one turn
- Return one final structured result instead of dozens of intermediate results
- Preserve existing confirmation, preview, timeout, and output-limit behavior

## Scope

### In Scope (v1)

- Agent-mode access plus readonly `gptel-plan` access with a separate readonly profile
- Programmatic orchestration of existing nucleus tools
- Restricted runtime with explicit capability wrappers
- Timeouts, result truncation, and audit-friendly execution logs
- Prompt guidance and examples for when to prefer `Programmatic`

### Out of Scope (v1)

- Full mutating Programmatic access in plan mode
- Readonly/introspector subagent mutating access
- Arbitrary Elisp evaluation
- Direct process, network, or file mutation primitives outside existing tools
- Replacing `RunAgent` for delegation-heavy research tasks

## Non-Goals

- This is **not** a general `Eval` replacement
- This is **not** a sandbox based only on prompt instructions
- This is **not** a way to bypass `:confirm` or preview flows on mutating tools
- This is **not** a provider-specific optimization layer

## Security Model

The repository's existing learning is explicit: system prompts are not a real
sandbox. Therefore `Programmatic` must enforce safety in code, not in prompt
text.

### Hard Constraints

- Expose `Programmatic` in both readonly and agent toolsets, but switch capability profile by mode
- Execute user-generated code in a dedicated sandbox entrypoint
- Provide a narrow wrapper API that can call registered tools by name
- Do **not** expose general `eval`, process, file, network, or buffer mutation
  functions to the generated program
- Reuse existing tool ACLs, confirmations, and workspace-boundary checks
- Enforce execution timeout, max tool-call count, and max output size

### Allowed Execution Pattern

Generated code should orchestrate through explicit helper functions such as:

```elisp
(tool-call "Grep" :pattern "TODO" :path ".")
(tool-call "Read" :file_path "foo.el" :start_line 1 :end_line 80)
(result "Final synthesized answer")
```

The generated program does not receive raw access to Emacs primitives. It only
receives the orchestrator helpers and inert data utilities needed to compose
results.

### Safety Defaults

- Default timeout: 15s
- Default max nested tool calls: 25
- Default max returned result: reuse existing truncation pattern used by Bash /
  subagents
- Any mutating tool still triggers its normal `:confirm` / preview behavior
- If the sandbox rejects a form, return a clear tool error to the LLM

## Position in the Existing Architecture

`Programmatic` sits above the existing tool layer. It should orchestrate tools,
not duplicate them.

### Existing Layers

```text
prompts/presets
    -> tool selection
        -> tool registry (`gptel-tools.el`)
            -> ACL / confirmation / preview wrappers
                -> concrete tools (`Bash`, `Grep`, `Code_*`, etc.)
```

### New Layer

```text
prompts/presets
    -> Programmatic tool
        -> sandbox wrapper API
            -> existing registered tools
                -> existing ACL / confirmation / preview wrappers
```

## Files to Add / Update

### New Files

- `lisp/modules/gptel-sandbox.el` — restricted evaluator + wrapper environment
- `lisp/modules/gptel-tools-programmatic.el` — tool entrypoint + orchestration
- `tests/test-programmatic.el` — ERT coverage for sandbox and orchestration

### Existing Files to Update

- `lisp/modules/gptel-tools.el` — require/register the new tool
- `lisp/modules/nucleus-tools.el` — add `Programmatic` to mode-appropriate toolsets
- `lisp/modules/nucleus-presets.el` — ensure agent contracts stay correct
- `lisp/modules/gptel-ext-security.el` — optional explicit deny rule for
  readonly presets as defense in depth
- `assistant/prompts/code_agent.md` — document when to use `Programmatic`
- `assistant/README.md` — document behavior, limits, and examples

## Tool Contract

### New Tool: `Programmatic`

```elisp
(gptel-make-tool
 :name "Programmatic"
 :function #'gptel-tools-programmatic--execute
 :description "Execute restricted Emacs Lisp that orchestrates multiple existing tool calls."
 :args '((:name "code" :type string :description "Restricted Emacs Lisp program"))
 :category "gptel-agent"
 :confirm t
 :include t)
```

### Usage Guidance

Prefer `Programmatic` when all of the following are true:

- the task needs 3+ tool calls
- the calls are tightly coupled
- intermediate results do not need to be shown to the model turn-by-turn
- the work is orchestration, not delegation to an autonomous subagent

Prefer existing tools when:

- one direct tool call is enough
- a structured editor like `Code_Replace` already solves the task directly
- the task needs independent reasoning across broad search spaces (`RunAgent`)

## Implementation Plan

### Phase 1: Sandbox Core

- [x] Create `lisp/modules/gptel-sandbox.el`
- [x] Define the restricted evaluation entrypoint
- [x] Implement wrapper helpers (`tool-call`, `result`, small data helpers)
- [x] Enforce timeout, max calls, and output truncation
- [x] Reject disallowed forms with explicit error messages

### Phase 2: Tool Integration

- [x] Create `lisp/modules/gptel-tools-programmatic.el`
- [x] Register `Programmatic` from `lisp/modules/gptel-tools.el`
- [x] Add `Programmatic` to `:nucleus` in `lisp/modules/nucleus-tools.el`
- [x] Expose readonly `Programmatic` in `:readonly` while keeping it out of
  `:researcher`, `:explorer`, and `:reviewer`
- [x] Confirm existing ACL/preview/confirm wrappers still apply transitively

### Phase 3: Prompt + UX

- [x] Update `assistant/prompts/code_agent.md` with decision rules and examples
- [x] Add concise examples showing orchestration vs plain tool use
- [~] Decide whether a dedicated preview is needed for multi-step mutating runs
- [x] Ensure failure messages teach the model how to recover

### Phase 4: Verification

- [x] Add `tests/test-programmatic.el`
- [x] Add ERT tests for sandbox rejection cases
- [x] Add ERT tests for allowed orchestration cases
- [x] Add tests for timeout, call-count, and truncation behavior
- [x] Add tests proving readonly presets can access only readonly `Programmatic`
- [x] Run targeted benchmarks against representative multi-tool workflows

## Current Reality

Implemented in the current repo:

- Restricted serial sandbox in `lisp/modules/gptel-sandbox.el`
- Registered `Programmatic` tool in `lisp/modules/gptel-tools-programmatic.el`
- Mode-aware exposure via `:readonly` and `:nucleus` toolsets with separate readonly/agent capability profiles
- Structured result rendering and a small safe expression/data subset
- Native confirmation UI integration for nested Programmatic mutating calls
- Readonly Programmatic support in `gptel-plan` with a separate readonly tool allowlist
- Prompt examples for read-only and preview-backed patch workflows
- ERT coverage in `tests/test-programmatic.el` and
  `tests/test-tool-confirm-programmatic.el`

Still open:

- Aggregate preview for multi-step mutating runs
- Benchmarking against ordinary multi-tool round trips
  - Initial local benchmark harness added in `lisp/modules/gptel-programmatic-benchmark.el`
  - Helper script added at `scripts/benchmark-programmatic.sh`
  - Read-only workflow currently shows ~2.98x simulated end-to-end speedup and ~18.12% transcript reduction with one Programmatic turn versus three ordinary tool turns
  - Mutating preview-backed workflow is also covered so benchmark results now include a representative `Read -> Edit(diff)` path, not only read-only orchestration
- Decide whether async orchestration beyond nested async tools is worthwhile

## Testing Matrix

### Security Tests

- Reject direct `eval`
- Reject process creation and shell escape attempts
- Reject file mutation primitives unless they happen through existing tools
- Reject readonly preset access
- Verify workspace ACL checks still fire inside programmatic calls

### Functional Tests

- Successful multi-call read-only orchestration
- Successful orchestration that invokes a mutating tool and triggers confirm
- Correct result marshalling back to the model
- Correct propagation of tool errors into final output

### Performance Tests

- Baseline: repeated `Grep` / `Read` workflow via normal tool_use
- Compare against equivalent `Programmatic` orchestration
- Measure end-to-end elapsed time and response payload size

## Success Criteria

- A single `Programmatic` call can replace a 3-10 step tool chain
- Readonly modes cannot invoke it
- Mutating operations still require confirmation / preview
- Sandbox escapes fail closed with explicit error text
- Tests cover both safe paths and rejection paths
- Benchmarks show a clear reduction in tool round trips and payload chatter

## Open Questions

- Should mutating multi-tool runs get an aggregate preview in addition to the
  per-tool preview/confirm flow?
- Should `Programmatic` support async tool composition in v1, or only serial
  orchestration?
- Should the result contract be plain text only in v1, or allow structured
  plist/alist JSON-style returns?

## Archived Context

The prior AST-tooling roadmap is complete and should eventually move to
`CHANGELOG.md` or `docs/solutions/`. Current implementation lives under:

- `lisp/modules/gptel-tools-code.el`
- `lisp/treesit-agent-tools.el`
- `lisp/treesit-agent-tools-workspace.el`

## References

- Cloudflare Code Mode: https://blog.cloudflare.com/code-mode/
- Anthropic Programmatic Tool Calling: https://platform.claude.com/docs/en/agents-and-tools/tool-use/programmatic-tool-calling
