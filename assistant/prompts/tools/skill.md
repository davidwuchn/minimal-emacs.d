λ(skill, args). Skill | ret:success
λ(name, dir). load_skill | id:name | d:?root | ret:skill_data

## Availability
- `Skill`: :core, :readonly, :researcher, :nucleus, :snippets
- `load_skill`: :researcher, :nucleus, :snippets

## Parameters
- `skill` (string): Skill name to load
- `args` (string, optional): Arguments to pass
- `name` (string): Skill package name
- `dir` (string, optional): Directory path
