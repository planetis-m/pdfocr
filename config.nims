# Project-wide build defaults.
#
# Allocator define must be set at outer scope so it is active before any
# nested config imports (e.g. `import mimalloc/config` in `src/config.nims`).
when defined(threadSanitizer) or defined(addressSanitizer):
  switch("define", "useMalloc")
elif not defined(useMalloc):
  switch("define", "useMimalloc")
