rdmd --force --build-only test.d > /dev/null 2>&1 && ./test 2>&1 | grep -qF true
