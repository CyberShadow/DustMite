#!/bin/sh
set -eu

rm -rf src
mkdir src
cd src

touch file
mkdir dir
ln -s file file-link
ln -s dir dir-link
ln -s file-link link-link
ln -s . recursive-link
ln -s nonexistent broken-link
