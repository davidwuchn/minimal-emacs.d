💡 prompt-build syntax + load-order fix

Commit `ff48cced` (frontier aggregate refactor) copy-pasted a broken
dolist loop into `gptel-auto-experiment--get-axis-stats`, replacing the
correct TSV reading loop with undefined variables (all-exp, experiments).
This caused End-of-file parse errors in the prompt-build module, which
blocked ALL auto-workflow daemon init.

Also `gptel-tools-agent-subagent` lacked explicit `(require
'gptel-tools-agent-git)`, causing void-function errors when nucleus tool
verification ran before the git module loaded. The `declare-function`
declaration is not sufficient to ensure the defining file is loaded.

Fix: restore the correct TSV loop, add explicit require.
