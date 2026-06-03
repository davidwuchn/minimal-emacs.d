When a function accepts an optional string parameter with mixed usage (as both a
string value and as part of a string-typed collection), use `(stringp x)` as the
guard rather than just `x`. This ensures type consistency: if the parameter is
later checked with `(stringp x)` elsewhere in the function body, the initial
guard should match. Example: `(when (stringp target-file) ...)` instead of
`(when target-file ...)` when the inner usage already guards with `(stringp
target-file)`.