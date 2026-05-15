# Tool Marker Architecture

**Category:** architecture  
**Markers:** 🔁 pattern

## Insight

Tool classification must flow from a single source of truth (marker registry), not scattered hardcoded lists. Pattern: define marker traits on tools, derive all classification lists from markers at load time.

10 markers cover all classification needs: `:can-edit`, `:can-read`, `:symbolic`, `:web`, `:memory`, `:delegates`, `:requires-project`, `:plan-excluded`, `:sandbox-excluded`, `:file-inspector`.

Key derivation rules:
- Primary toolsets (`:readonly`, `:nucleus`, `:executor`) use `(:derived INCLUDE EXCLUDE)` — computed from markers
- Subagent toolsets remain hand-curated (role-specific inclusions not expressible by markers alone)
- Sandbox profiles derive from markers minus `:sandbox-excluded` and `:delegates`
- Progressive shortening works for both sync (Code_Map, Code_Inspect, Diagnostics) and async tools (Grep — wrap the callback result before delivery)

Anti-pattern: adding a tool to one list but forgetting another. Marker system prevents this — add tool name + markers once, all derived lists update automatically.
