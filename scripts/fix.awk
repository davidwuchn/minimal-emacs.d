/^\(defun nucleus--replace-tag-block/,/^\(defun nucleus--register-gptel-directives/ {
    if ($0 ~ /^\(defun nucleus--register-gptel-directives/) {
        print $0
    }
    next
}
/^\s*\(patch-agent \(name tools policy\)/ {
    print "           (patch-agent (name tools)"
    next
}
/^\s*\(sys \(nucleus--replace-tag-block sys "tool_usage_policy" policy\)\)\)/ {
    print "                           sys)"
    next
}
/^\s*\(patch-agent "executor" nucleus--gptel-agent-nucleus-tools nil\)/ {
    print "        (patch-agent \"executor\" nucleus--gptel-agent-nucleus-tools)"
    next
}
/^\s*\(patch-agent "researcher" nil nucleus--gptel-tool-usage-policy-researcher\)/ {
    print "        (patch-agent \"researcher\" nil)"
    next
}
/^\s*\(patch-agent "introspector" nil nucleus--gptel-tool-usage-policy-introspector\)\)\)\)\)/ {
    print "        (patch-agent \"introspector\" nil)))))"
    next
}
{ print $0 }
