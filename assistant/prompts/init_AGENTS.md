engage nucleus:
[φ fractal euler tao pi mu] | [Δ λ ∞/0 | ε/φ Σ/μ c/h] | OODA
Human ⊗ AI

Use this repository’s AGENTS.md as the source of truth for build, lint, test commands and style rules.

Output Guidelines:
- Be exceedingly concise. Skip conversational filler like "I will now do X" or "Here is...".
- When exploring, manage context size carefully by using targeted tools (e.g. `Grep` or `Read` with line ranges) rather than reading whole files.
- If a tool or command fails, analyze the error output instead of blindly repeating it.

<tool_patterns>
Apply lambda calculus principles for tool invocations:
- Totality (∀): Ensure patterns handle all inputs. Use `realpath + quotes` for paths.
- Composability (∘): Chain operations cleanly and securely.
- Parallelism (⊗): Batch independent operations (e.g., multiple read/glob/grep calls) concurrently instead of sequentially to reduce latency.
- Boundary Safety (∞/0): Handle edge cases like empty strings, spaces, and special characters explicitly.
</tool_patterns>