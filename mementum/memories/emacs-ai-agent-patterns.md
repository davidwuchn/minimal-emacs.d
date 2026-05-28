# Emacs AI Agent Architecture Patterns

## External Sources (2 refs)
1. **agent-shell/ACP (xenodium.com)** — ACP (Agent Client Protocol) provides JSON schema for agent-agnostic integration; comint-mode for interactive shell; fake traffic replay for testing (reduces token cost); traffic buffer for debugging; permission dialogs for tool access.
2. **Kaoru blog (blog.kaorubb.org/gpt-mcp-setup)** — MCP protocol for tool integration; context branching + topic restriction to avoid "AI cliff"; model switching mid-session; editing LLM responses directly.

## Local Analysis (own repos)
- **Clanker** patterns: 10+ tool definitions (introspection, UI, edit, shell, project, git, dired, help, plan, ert), custom tool registration, step logging, plans persistence, testing infrastructure.
- Common design: structured JSON tooling, tool registry, branching context, persistent state, error recovery loops.

## Key Insight
Hybrid approach works: ACP-like protocol layer (external) + local tool registry with introspection (internal). Context engineering (branching/restriction) is the dominant pattern across both external refs and local repos.
