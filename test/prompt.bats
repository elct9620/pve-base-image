#!/usr/bin/env bats

setup() {
  load test_helper
  TEST_INPUT="${BATS_TEST_TMPDIR}/input"
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
  local OPTIONS=("a" "b" "c")
  prompt_menu RESULT "Pick one:" "b" OPTIONS
  [[ "${RESULT}" == "b" ]]
}

@test "prompt_menu: should select by number" {
  fake_input "2"
  local OPTIONS=("a" "b" "c")
  prompt_menu RESULT "Pick one:" "a" OPTIONS
  [[ "${RESULT}" == "b" ]]
}

@test "prompt_menu: should skip when variable already set" {
  RESULT="preset"
  fake_empty_input
  local OPTIONS=("a" "b" "c")
  prompt_menu RESULT "Pick one:" "a" OPTIONS
  [[ "${RESULT}" == "preset" ]]
}

@test "prompt_menu: should display labels when provided" {
  fake_empty_input
  local OPTIONS=("a" "b")
  local LABELS=("Alpha" "Beta")
  output=$(prompt_menu RESULT "Pick one:" "a" OPTIONS LABELS 2>&1)
  [[ "${output}" == *"Alpha"* ]]
  [[ "${output}" == *"Beta"* ]]
}

@test "prompt_menu: should exit on invalid selection" {
  fake_input "99"
  local OPTIONS=("a" "b")
  run prompt_menu RESULT "Pick:" "a" OPTIONS
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"Invalid selection"* ]]
}

@test "prompt_menu: should select first option by number" {
  fake_input "1"
  local OPTIONS=("a" "b" "c")
  prompt_menu RESULT "Pick one:" "b" OPTIONS
  [[ "${RESULT}" == "a" ]]
}

@test "prompt_menu: should select last option by number" {
  fake_input "3"
  local OPTIONS=("a" "b" "c")
  prompt_menu RESULT "Pick one:" "a" OPTIONS
  [[ "${RESULT}" == "c" ]]
}

@test "prompt_menu: should accept default not in options" {
  fake_empty_input
  local OPTIONS=("a" "b")
  prompt_menu RESULT "Pick one:" "z" OPTIONS
  [[ "${RESULT}" == "z" ]]
}

@test "install.sh: should not fail with unbound BASH_SOURCE in pipe mode" {
  local script="${BATS_TEST_DIRNAME}/../install.sh"
  local result
  result="$(bash -u "${script}" </dev/null 2>&1 || true)"
  [[ "${result}" != *"BASH_SOURCE: unbound variable"* ]]
}

@test "prompt_menu: should work without labels" {
  fake_empty_input
  local OPTIONS=("x" "y")
  output=$(prompt_menu RESULT "Pick one:" "x" OPTIONS 2>&1)
  [[ "${output}" == *"[1] x (default)"* ]]
  [[ "${output}" == *"[2] y"* ]]
}
