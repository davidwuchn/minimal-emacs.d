awk '
/agent-sys \(nucleus--replace-tag-block agent-sys "tool_usage_policy"/ {
    print "             (agent-sys (if agent-sys"
    print "                            (nucleus--replace-tag-block agent-sys \"tool_usage_policy\""
    print "                                                       nucleus--gptel-tool-usage-policy-agent)"
    print "                          agent-sys))"
    getline
    next
}
{ print $0 }
' lisp/nucleus-config.el > /tmp/out.el
mv /tmp/out.el lisp/nucleus-config.el
