switch("path", "$projectDir/../src")
# (the system's malloc: memory let go of goes back to the system -- Nim's own
# allocator keeps every page it took, on each thread, and the programs only
# grow; see retroui/memwatch)
switch("define", "useMalloc")
when defined(windows): switch("app", "gui")
