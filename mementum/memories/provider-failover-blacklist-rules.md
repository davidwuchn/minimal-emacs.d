# Provider Failover Should Not Blacklist for Transient Errors

## Problem
`gptel-auto-workflow--activate-provider-failover` always added backends to `rate-limited-backends`, even for timeouts and parse errors.

This caused CF-Gateway to be blacklisted for "Could not parse HTTP response" (which was actually the reasoning_content bug), making it unavailable for future retries.

## Solution
Added `skip-blacklist` parameter to `activate-provider-failover`:
- `nil` (default): Blacklist for rate limits and hard quotas
- `t`: Switch to fallback WITHOUT blacklisting (for timeouts, parse errors, connection failures)

Updated `maybe-activate-rate-limit-failover` to pass `skip-blacklist=t` for transient errors branch.

## Key Rule
**Only blacklist for:**
- Rate limit errors (429, throttling)
- Hard quota exhaustion (usage limit exceeded)

**Do NOT blacklist for:**
- Timeouts
- Parse errors
- Connection failures
- Server errors (5xx)

## Files
- `lisp/modules/gptel-tools-agent-error.el:104-154`

## Tags
provider-failover, blacklisting, rate-limiting, transient-errors, cf-gateway