# ✅ gptel Stream Sentinel Recursion Guard

tags: gptel, sentinel, recursion, Lisp-nesting, max-lisp-eval-depth

## Symptom
`error in process sentinel: Lisp nesting exceeds 'max-lisp-eval-depth': 12001`
Daemon crashed repeatedly with deep recursion in process sentinels.

## Root Cause
`gptel-curl--stream-cleanup` in `packages/gptel/gptel-request.el` had NO recursion guard. Only `gptel-curl--sentinel` had the depth check. When callbacks spawned new requests from within stream-cleanup, the sentinel chain could recurse infinitely.

## Fix
Added `gptel-curl--sentinel-depth` guard (threshold=20) to `gptel-curl--stream-cleanup`. Both sentinel functions now share the same recursion protection. Defvar moved before both function definitions.

## Files Changed
- packages/gptel/gptel-request.el: stream-cleanup now checks depth before processing
