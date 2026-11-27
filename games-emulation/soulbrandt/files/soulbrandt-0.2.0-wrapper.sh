#!/bin/sh
# Setup lifts the game from the player's own copy and compiles it. Upstream's setup downloads its own Python and
# clang for that; these are the system's. Each can still be set in the environment.
: "${DES_SETUP_PYTHON:=@PYTHON@}"
: "${DES_SETUP_CC:=@CLANG@}"
: "${DES_SETUP_LD:=@CLANG@}"
export DES_SETUP_PYTHON DES_SETUP_CC DES_SETUP_LD
exec "@DIST@/Soulbrandt" "$@"
