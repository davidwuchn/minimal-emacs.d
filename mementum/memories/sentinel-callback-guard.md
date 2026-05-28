💡 sentinel callback nil guard

gptel-request.el has two process sentinel functions:
gptel-curl--stream-cleanup (streaming) and gptel-curl--sentinel
(non-streaming). Both call funcall (plist-get info :callback), which can
return nil if the callback wasn't stored in FSM info (e.g., race
condition or missing :callback key). This causes void-function nil
errors that break mementum synthesis and kill kept experiments.

The stream-cleanup already had a guard but the sentinel didn't. Added
my/gptel--ensure-callback-function helper that patches nil callbacks to
#'ignore, applied to BOTH sentinels via :around advice.
