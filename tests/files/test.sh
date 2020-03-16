echo 4 > expected && cat *.txt | grep -c a > result && diff expected result
