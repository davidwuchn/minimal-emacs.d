# Allium async fan-out needs FIFO serialization

When multiple async `gptel-request` calls fan out from one workflow cycle, Emacs can exhaust pipes/file descriptors even though each request is “only async”. The fix is to serialize the request family behind one shared FIFO queue and release the slot with `unwind-protect` in the callback wrapper.

Key points:
- Use FIFO, not a stack (`push`/`pop`), so call order stays deterministic.
- Keep the sync fallback path unchanged when `gptel-request` is unavailable.
- Align hardcoded fan-out caps with existing config knobs instead of adding a second limit.
