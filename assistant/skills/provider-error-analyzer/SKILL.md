---
name: provider-error-analyzer
description: |
  Analyzes LLM provider error messages to determine retry strategy, failover candidates,
  and root cause. Supports multiple providers (OpenAI, Anthropic, Google, local models).
version: 1.0
evolve-script: evolve_patterns.py
metadata:
  category: reliability
  author: auto-workflow
  evolution-stats:
    total-experiments: 870

---
# Provider Error Analyzer

## Overview

Different LLM providers return different error formats. This skill maps error messages to categories and determines the best recovery strategy.

## Error Categories

### Rate Limit (429)
**Pattern**: `usage limit exceeded`, `rate_limit_error`, `too many requests`

**Providers**:
- **OpenAI**: `RateLimitError`, `429 Too Many Requests`
- **Anthropic**: `overloaded_error`, `529 Overloaded`
- **Google**: `ResourceExhausted`, `429`
- **Local**: Varies by reverse proxy

**Strategy**: 
- Exponential backoff: 1s, 2s, 4s, 8s, 16s
- Max retries: 3
- If persistent: Failover to alternate provider

### Quota Exhausted (429/403)
**Pattern**: `insufficient_quota`, `allocated quota exceeded`, `billing_hard_limit_reached`, `hard limit reached`, `quota exceeded`

**Providers**:
- **OpenAI**: `insufficient_quota` (1004)
- **Anthropic**: `quota_exceeded` (429)
- **Google**: `QuotaExceeded` (429)

**Strategy**:
- Mark provider as unavailable for this billing cycle
- Immediate failover to next provider
- Do NOT retry (wastes time)

### Authentication (401)
**Pattern**: `invalid_api_key`, `unauthorized`, `token is unusable`, `Authentication failed`

**Providers**:
- **OpenAI**: `invalid_api_key` (401)
- **Anthropic**: `authentication_error` (401)
- **Google**: `Unauthenticated` (401)

**Strategy**:
- Check API key configuration
- If using key rotation, try next key
- If persistent: Mark provider unavailable, alert user

### Content Filter (400)
**Pattern**: `content_filter`, `invalid_request_error`, `Bad request`

**Strategy**:
- Sanitize prompt (remove PII, reduce length)
- Retry once with sanitized content
- If persistent: Skip this experiment

### Server Error (500/502/503/529)
**Pattern**: `server_error`, `bad_gateway`, `service_unavailable`, `overloaded`, `cluster overloaded`

**Providers**:
- **OpenAI**: `server_error` (500)
- **Anthropic**: `overloaded_error` (529)
- **Google**: `InternalServerError` (500)

**Strategy**:
- Exponential backoff: 2s, 4s, 8s
- Max retries: 5
- If persistent: Failover

### Timeout (408/504)
**Pattern**: `timeout`, `Request timeout`, `Gateway timeout`

**Strategy**:
- Reduce request complexity (shorter prompt, smaller max_tokens)
- Retry once with reduced scope
- If persistent: Skip or reduce timeout threshold

### Network Error
**Pattern**: `Connection refused`, `Network error`, `DNS resolution failed`

**Strategy**:
- Check network connectivity
- Retry with exponential backoff
- If persistent: Mark provider unavailable

## Provider Failover Order

```
Primary:    kimi (cost-effective)
Fallback 1: openai (reliable)
Fallback 2: anthropic (high quality)
Fallback 3: google (backup)
Local:      ollama/lmstudio (always available)
```

## Scripts

- `scripts/classify_error.py` - Classify error message into category
- `scripts/recommend_strategy.py` - Recommend retry/failover strategy
- `scripts/update_patterns.py` - Learn new error patterns from logs

## Integration

```elisp
;; Classify error
(let ((error-msg "usage limit exceeded (2056)"))
  (provider-error-classify error-msg))
;; => (:category 'rate-limit :retryable t :backoff 2)

;; Get failover candidate
(provider-error-failover-candidate 'kimi)
;; => (:provider 'openai :model 'gpt-4)
```

## Pattern Updates

When encountering new error formats:
1. Add pattern to `references/error-patterns.md`
2. Run `scripts/update_patterns.py`
3. Commit with message: `🔄 update provider-error patterns`

## Evolved Error Patterns

Based on analysis of experiment errors.

| Pattern | Category | Action | Frequency | Regex |
|---------|----------|--------|-----------|-------|
