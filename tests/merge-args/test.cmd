@rdmd --tmpdir=. --build-only test.d && test 2>&1 | grep -qF true
