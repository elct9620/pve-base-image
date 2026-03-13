#!/usr/bin/env bats

setup() {
  load test_helper
  TEST_INPUT="${BATS_TEST_TMPDIR}/input"
}

# Write simulated user input to file and point TTY_INPUT to it
fake_input() {
  printf '%s\n' "$1" > "${TEST_INPUT}"
  TTY_INPUT="${TEST_INPUT}"
}

fake_empty_input() {
  printf '' > "${TEST_INPUT}"
  TTY_INPUT="${TEST_INPUT}"
}

# --- prompt ---

@test "prompt: should use default when input is empty" {
  fake_empty_input
  prompt RESULT "Enter value:" "default_val"
  [[ "${RESULT}" == "default_val" ]]
}

@test "prompt: should use user input when provided" {
  fake_input "custom_val"
  prompt RESULT "Enter value:" "default_val"
  [[ "${RESULT}" == "custom_val" ]]
}

@test "prompt: should skip when variable already set" {
  RESULT="preset"
  fake_empty_input
  prompt RESULT "Enter value:" "default_val"
  [[ "${RESULT}" == "preset" ]]
}

# --- prompt_menu ---

@test "prompt_menu: should select default when input is empty" {
  fake_empty_input
  prompt_menu RESULT "Pick one:" "b" "a" "b" "c"
  [[ "${RESULT}" == "b" ]]
}

@test "prompt_menu: should select by number" {
  fake_input "2"
  prompt_menu RESULT "Pick one:" "a" "a" "b" "c"
  [[ "${RESULT}" == "b" ]]
}

@test "prompt_menu: should skip when variable already set" {
  RESULT="preset"
  fake_empty_input
  prompt_menu RESULT "Pick one:" "a" "a" "b" "c"
  [[ "${RESULT}" == "preset" ]]
}

@test "prompt_menu: should display labels when provided via --" {
  fake_empty_input
  output=$(prompt_menu RESULT "Pick one:" "a" "a" "b" -- "Alpha" "Beta" 2>&1)
  [[ "${output}" == *"Alpha"* ]]
  [[ "${output}" == *"Beta"* ]]
}

@test "prompt_menu: should exit on invalid selection" {
  fake_input "99"
  run prompt_menu RESULT "Pick:" "a" "a" "b"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"Invalid selection"* ]]
}

@test "prompt_menu: should work without labels (no --)" {
  fake_empty_input
  output=$(prompt_menu RESULT "Pick one:" "x" "x" "y" 2>&1)
  [[ "${output}" == *"[1] x (default)"* ]]
  [[ "${output}" == *"[2] y"* ]]
}
