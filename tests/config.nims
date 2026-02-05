# Shared config for tests.
switch("path", "$projectdir/../src")

when defined(windows):
  switch("cc", "vcc")
