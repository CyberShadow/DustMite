dmd src.d > /dev/null 2>&1 && ./src 2>&1 | grep -qF true
