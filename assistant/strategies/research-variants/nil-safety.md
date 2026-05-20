## Research Focus: Nil-Safety Hunting

Find functions that assume their inputs are non-nil without checking.
For each: add `(when (stringp x))`, `(proper-list-p)`, or `ignore-errors` guards.
Prefix the change with: `[nil-safety]`
