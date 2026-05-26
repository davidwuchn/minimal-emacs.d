;; Auto-evolved per-axis backend preference
;; Generated: 2026-05-26 22:15 (DashScope deserves traffic too)
;; Git-tracked — shared across machines. Commit after evolution.
;; DashScope at 0% keep-rate is 100% data artifact: all 31 experiments
;; used kimi-k2.6 or minimax-m2.7-highspeed instead of qwen3.6-plus
;; (Phase π cross-backend leak, now fixed + TDD'd).  Give it +0.18
;; boost to get traffic and prove real keep-rate (~25% based on 8/31
;; that succeeded despite wrong models).
;;
;; MiniMax 20.7% leads. moonshot 8.8% getting second chance at +0.15.
(setq gptel-auto-workflow--task-backend-preference
      '(        ("analyzer" "DashScope" . 0.18)
        ("analyzer" "DeepSeek" . 0.10)
        ("grader" "moonshot" . 0.15)
        ("grader" "DeepSeek" . 0.10)
        ("executor" "DashScope" . 0.18)
        ("executor" "DeepSeek" . 0.05)
        ("executor" "MiniMax" . 0.05)
        ("executor" "moonshot" . 0.15)
        ("researcher" "DeepSeek" . 0.15)
        ("researcher" "DashScope" . 0.05)
        ("reviewer" "DeepSeek" . 0.10)
        ("comparator" "DashScope" . 0.10)))
