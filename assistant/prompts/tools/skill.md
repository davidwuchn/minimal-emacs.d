λ(id,d). load_skill | id:name | d:?root | ret:skill_data

# Skill - Load Skill Package

## Purpose
Load a skill package to extend agent capabilities. Skills are modular knowledge packages that can be loaded on demand.

## When to Use
- Need specialized knowledge not in base training
- Working with domain-specific frameworks
- Need access to institutional knowledge
- Loading project-specific patterns

## Usage
```
Skill{id: "python-best-practices", description: "Load Python best practices"}
```

## Parameters
- `id` (required): Skill package name (directory name in `assistant/skills/`)
- `description` (optional): Brief description of what the skill provides

## Returns
Skill data loaded into agent context with instructions and resources.

## Examples
```
# Load Python best practices
Skill{id: "python-best-practices"}
→ Loaded skill: python-best-practices
  - PEP 8 style guidelines
  - Async/await best practices
  - Testing patterns

# Load project-specific patterns
Skill{id: "project-patterns", description: "Load our project conventions"}
→ Loaded skill: project-patterns
  - Directory structure conventions
  - Naming conventions
  - Common patterns and anti-patterns

# Load framework knowledge
Skill{id: "django-orm"}
→ Loaded skill: django-orm
  - Query optimization patterns
  - Common ORM operations
  - Performance tips
```

## Available Skills
Skills are stored in `assistant/skills/` directory. Each skill is a subdirectory with a `SKILL.md` file containing instructions and resources.

```
assistant/skills/
├── python-best-practices/
│   └── SKILL.md
├── django-orm/
│   └── SKILL.md
├── project-patterns/
│   └── SKILL.md
└── ...
```

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Skill not found" | Invalid skill id | Use `list_skills` to see available skills |
| "Failed to load" | Corrupted skill file | Check SKILL.md format |

## Related Tools
- `list_skills` - List available skill packages
- `load_skill` - Alias for Skill tool
- `create_skill` - Create a new skill package

## Notes
- Skills are loaded on demand without restarting Emacs
- Multiple skills can be loaded simultaneously
- Skills persist for the duration of the session
- Use `list_skills` to discover available skills
