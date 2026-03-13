#!/usr/bin/env bash
# Test helper — sources install.sh (only helper functions, guard skips main)

INSTALL_SH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install.sh"

export TTY_INPUT=/dev/stdin

source "${INSTALL_SH}"
set +eu

# --- Test input helpers ---

fake_input() {
  printf '%s\n' "$1" > "${TEST_INPUT}"
  TTY_INPUT="${TEST_INPUT}"
}

fake_empty_input() {
  printf '' > "${TEST_INPUT}"
  TTY_INPUT="${TEST_INPUT}"
}
