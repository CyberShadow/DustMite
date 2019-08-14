DustMite test suite
===================

How to use this test suite:

You should perform the following steps before beginning work on DustMite,
as well as before committing any non-trivial changes to DustMite or its algorithms.

1. Make sure you have DMD 2.080 as the first `dmd` binary in your `PATH`.
   (See `testSuiteDMDVersion` in `runtests.d` for an explanation.)

2. Make sure your git checkout of the tests directory is clean (no added/deleted files in the `tests` directory).
   If it's not, reset your work tree accordingly.

3. Run the `runtests.d` program. (It will compile DustMite as part of its execution.)

4. Use `git status` and `git diff` to check the effects of running the tests.

   - Any changes to test output should be accounted for, i.e. a desirable effect of changes in DustMite.

   - All unexpected changes indicate a problem (with DustMite, the test suite, or your environment).
     Do not commit these changes without understanding their cause.

   - All commits with changes in DustMite which also change test output should be accompanied by these changes in the test output.
     Do not commit DustMite changes without also including the test output changes they cause.
