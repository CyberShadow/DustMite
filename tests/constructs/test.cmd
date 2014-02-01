@dmd -L/ENTRY:_mainCRTStartup test.d > nul 2>&1 && test 2>&1 | grep -qF true
