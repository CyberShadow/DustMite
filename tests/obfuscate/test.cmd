@rdmd --force --build-only test.d > nul 2>&1 && test 2>&1 | grep -qF "Hello, world"
