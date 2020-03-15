rdmd --force --build-only test.d 2> /dev/null 2>&1 && ./test 2>&1 | grep -qF true
