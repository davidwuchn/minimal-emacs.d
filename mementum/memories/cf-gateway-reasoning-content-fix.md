# CF-Gateway Returns reasoning_content Not content

## Problem
CF-Gateway with kimi-k2.6 returns LLM responses in `reasoning_content` field instead of `content`. The `content` field is null.

This causes gptel's OpenAI parser (`gptel--parse-response`) to return nil, which triggers "Could not parse HTTP response" errors.

## Evidence
Direct curl test shows:
```json
"message": {
  "content": null,
  "reasoning_content": "...actual response text..."
}
```

## Solution
Added advice around `gptel--parse-response` in `gptel-ext-backends.el`:
- Detects when CF-Gateway returns empty content with non-empty reasoning_content
- Falls back to returning reasoning_content as the response

## Verification
- Simple prompt (8s): works, returns in content
- Complex prompt (44s): **requires fix**, returns in reasoning_content
- With fix: 3316 chars result + 2582 chars reasoning captured correctly

## Files
- `lisp/modules/gptel-ext-backends.el:93-118`

## Tags
cf-gateway, gptel, parsing, reasoning-content, timeout