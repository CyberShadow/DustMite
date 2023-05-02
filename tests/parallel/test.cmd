@rdmd --tmpdir=. --build-only test.d > nul 2>&1 && test 2>&1 | grep -qF true
