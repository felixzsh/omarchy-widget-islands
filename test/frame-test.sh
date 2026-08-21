#!/usr/bin/env bash
# compat shim: frame-test.sh -> rails-test.sh
exec "$(dirname "$0")/rails-test.sh" "$@"
