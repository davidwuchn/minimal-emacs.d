;; Auto-evolved per-axis backend preference
;; Updated: 2026-05-31 — DeepSeek primary, DashScope timeout fix
;; DeepSeek handles complex prompts with thinking mode.
;; DashScope times out consistently on analyzer tasks.
;; MiniMax is fast for lightweight subagents.
(setq gptel-auto-workflow--task-backend-preference
      '(("analyzer" "DeepSeek" . 0.30)
        ("analyzer" "MiniMax" . 0.20)
        ("analyzer" "DashScope" . 0.10)
        ("grader" "DeepSeek" . 0.30)
        ("grader" "MiniMax" . 0.20)
        ("grader" "DashScope" . 0.10)
        ("executor" "DeepSeek" . 0.30)
        ("executor" "MiniMax" . 0.20)
        ("executor" "DashScope" . 0.10)
        ("researcher" "DeepSeek" . 0.30)
        ("researcher" "MiniMax" . 0.20)
        ("researcher" "DashScope" . 0.10)
        ("reviewer" "DeepSeek" . 0.30)
        ("reviewer" "MiniMax" . 0.20)
        ("reviewer" "DashScope" . 0.10)
        ("comparator" "DeepSeek" . 0.30)
        ("comparator" "MiniMax" . 0.20)
        ("comparator" "DashScope" . 0.10)))
