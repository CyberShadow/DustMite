@copy ..\program.d program.d && patch -p1 < src.patch && dmd -o- program.d > output.txt 2>&1 && grep -qF "42" output.txt
