💡 Grader rejects `<think>` block verification evidence as "planning, not execution"

The auto-workflow grader checks for verification command evidence (byte-compile,
syntax check, load test). Executor LLMs frequently put this output inside their
`<think>` reasoning blocks. The grader sees it but marks it FAIL because think
blocks are treated as planning, not execution.

Fix: extract verification-related lines from `<think>` blocks in
`gptel-auto-experiment--build-grading-output` and surface them as a
`VERIFICATION EVIDENCE FROM <think>` section appended to the grading output.
Also update the grader expected-criteria label to reference this section.

Also: tell the executor in `prompt-template.md` that the VERIFY section must
appear outside `<think>` blocks.
