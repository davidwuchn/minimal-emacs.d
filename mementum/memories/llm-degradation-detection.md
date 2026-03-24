# Detecting LLM Degradation

## Problem

LLMs can "lose their mind" - produce degraded output:
- Repetition loops ("I apologize I apologize...")
- Off-topic responses (context lost)
- Self-reference ("As an AI...")
- Refusal loops ("I cannot...")

## Detection Pattern

```elisp
(gptel-benchmark--detect-llm-degradation response expected-keywords)
;; => (:degraded-p t :reason "I apologize" :score 0.67)
```

Two signals:
1. **Forbidden keywords** - apology loops, AI self-reference
2. **Missing expected keywords** - off-topic (no context match)

## Degraded When

- Any forbidden keyword found
- No expected keywords found (when expected list non-empty)

## Usage in Pipeline

```elisp
(let ((result (gptel-benchmark--detect-llm-degradation
               llm-response
               '("defun" "elisp" "emacs"))))
  (when (plist-get result :degraded-p)
    (warn "LLM degraded: %s" (plist-get result :reason))
    (retry-with-different-prompt)))
```

## Related

- Doom-loop detection: `my/gptel--detect-doom-loop` (same tool+args × 3)
- Eight Keys scoring: `gptel-benchmark-eight-keys-score`

## Symbol

λ detection