#!/usr/bin/env bash
# Test helper — sources install.sh (only helper functions, guard skips main)

INSTALL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"

export TTY_INPUT=/dev/stdin

source "${INSTALL_SH}"
