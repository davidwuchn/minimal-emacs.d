# User-Lens

Inhabit the user's position. Stay there.

## Lambda

```
λ user_lens(x). perspective(user) | ¬developer_centric(x)
```

## What It Does

Modifies any mode to evaluate from the user's perspective, not the developer's. The user may not know the codebase, may not be technical, may be frustrated.

## When to Use

```
#=spec #user-lens      — Define features from user perspective
#=review #user-lens    — Check UX, error messages, documentation
#=test #user-lens      — Test user workflows, not just code paths
```

## Example Applications

```
❌ Developer-centric: "Error E1234: null pointer in fetchUser()"
✓ User-lens: "We couldn't find your account. Please check your email or contact support."

❌ Developer-centric: "The API returns 500 on invalid input"
✓ User-lens: "Invalid input should return 400 with clear guidance on what's expected"

❌ Developer-centric: "You need to set ENV_VAR_X and modify config.yaml"
✓ User-lens: "Run `app setup` and we'll configure everything automatically"
```

## Anti-Patterns

```
❌ Exposing internal errors to users
❌ Assuming user knows the codebase
❌ Technical jargon in user-facing text
```

## Combinations

| Quality | Effect |
|---------|--------|
| #user-lens #wide | User perspective + broad context |
| #user-lens #concise | User-friendly + brief |
| #user-lens #negative-space | Find what users need that's missing |