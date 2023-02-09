#!/bin/sh
set -eu
test -h file-link
test -h dir-link
test -h link-link
test -h recursive-link
test -h broken-link
