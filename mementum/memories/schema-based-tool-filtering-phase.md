## Schema-Based Tool Filtering by Phase

Implemented in `gptel-programmatic-benchmark.el` based on Efrit/steveyegge pattern.

### Functions
- `gptel-programmatic--filter-schema` - Filters tool schema list based on execution phase in state plist
- `gptel-programmatic--get-tools-for-phase` - Returns tool names for a given phase from a toolset

### Phase Definitions
| Phase | Allowed Markers | Excluded Markers |
|-------|----------------|------------------|
| :planning | :can-read, :memory, :web | :can-edit, :delegates |
| :execution | :can-read, :can-edit, :symbolic | :web |
| :validation | :can-read, :symbolic | :can-edit, :web, :delegates |
| :grading | :can-read | :can-edit, :web, :delegates |
| :research | :can-read, :memory, :web | :can-edit, :delegates |

### Usage
```elisp
;; Filter tools for planning phase
(gptel-programmatic--filter-schema current-tools '(:phase :planning))

;; Get tool names for execution phase
(gptel-programmatic--get-tools-for-phase :execution :nucleus)
```

### Integration Point
To integrate with FSM: call `gptel-programmatic--filter-schema` before each API call, passing current tool schema and state plist with `:phase` key.

### Bug Fixed
Also fixed pre-existing syntax error: unescaped quotes in string literal on line 149 (`"Read"` → `\"Read\"`).