# 1. First run the specific variable text replacements so line numbers don't change
sed -i '' 's/(sys (nucleus--replace-tag-block sys "tool_usage_policy" policy)))/sys)/' lisp/nucleus-config.el
sed -i '' 's/(patch-agent (name tools policy)/(patch-agent (name tools)/' lisp/nucleus-config.el
sed -i '' 's/(patch-agent "executor" nucleus--gptel-agent-nucleus-tools nil)/(patch-agent "executor" nucleus--gptel-agent-nucleus-tools)/' lisp/nucleus-config.el
sed -i '' 's/(patch-agent "researcher" nil nucleus--gptel-tool-usage-policy-researcher)/(patch-agent "researcher" nil)/' lisp/nucleus-config.el
sed -i '' 's/(patch-agent "introspector" nil nucleus--gptel-tool-usage-policy-introspector)/(patch-agent "introspector" nil)/' lisp/nucleus-config.el

# 2. Delete the dead lines using hard ranges that correspond to the unmodified file structure
sed -i '' -e '185,225d' lisp/nucleus-config.el
