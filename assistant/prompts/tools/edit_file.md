λ(path, old_str?, new_str_or_diff, diffp?). Edit | p:path | o:old_str(opt) | n:new_str_or_diff | d:diffp(opt) | ret:success/error

## Availability
- `Edit`: :core, :nucleus, :snippets

If target file is Clojure (.clj, .cljs, .cljc, .edn, .bb): DO NOT USE THIS TOOL. You MUST use the `clojure_edit` tool instead because it understands structural s-expressions and balanced parentheses.
