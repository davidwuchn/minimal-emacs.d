import re

with open("lisp/nucleus-config.el", "r") as f:
    text = f.read()

# Make nucleus-config.el own the hidden directives population
new_block = """(defvar my/gptel-hidden-directives
  '(nucleus-gptel-agent nucleus-gptel-plan Plan Agent explorer reviewer chatTitle compact init skillCreate completion rewrite)
  "Directives to hide from the transient menu.")

(provide 'nucleus-config)"""

text = text.replace("(provide 'nucleus-config)", new_block)

text = text.replace("nucleus-tools-readonly", "my/gptel-tools-readonly")
text = text.replace("nucleus-tools-action", "my/gptel-tools-action")
text = text.replace("nucleus--gptel-plan-readonly-tools", "my/gptel-plan-readonly-tools")
text = text.replace("nucleus--gptel-agent-action-tools", "my/gptel-agent-action-tools")
text = text.replace("nucleus-resolve-model", "my/gptel-resolve-model")

with open("lisp/nucleus-config.el", "w") as f:
    f.write(text)
