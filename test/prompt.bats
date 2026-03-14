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
  [[ "${result}" != *"return: can only"* ]]
}

@test "install.sh: qm create should include --agent enabled=1" {
  local script="${BATS_TEST_DIRNAME}/../install.sh"
  run grep -E '\-\-agent\s+enabled=1' "${script}"
  [[ "${status}" -eq 0 ]]
}

# --- prompt_confirm ---

@test "prompt_confirm: should default to yes on empty input" {
  fake_empty_input
  prompt_confirm RESULT "Enable feature?" "y"
  [[ "${RESULT}" == "yes" ]]
}

@test "prompt_confirm: should return no when input is n" {
  fake_input "n"
  prompt_confirm RESULT "Enable feature?" "y"
  [[ "${RESULT}" == "no" ]]
}

@test "prompt_confirm: should return yes when input is Y" {
  fake_input "Y"
  prompt_confirm RESULT "Enable feature?" "n"
  [[ "${RESULT}" == "yes" ]]
}

@test "prompt_confirm: should default to no when default is n and input is empty" {
  fake_empty_input
  prompt_confirm RESULT "Enable feature?" "n"
  [[ "${RESULT}" == "no" ]]
}

@test "prompt_confirm: should skip when variable already set" {
  RESULT="preset"
  fake_empty_input
  prompt_confirm RESULT "Enable feature?" "y"
  [[ "${RESULT}" == "preset" ]]
}

# --- detect_storages ---

@test "detect_storages: should return 1 when pvesm is not available" {
  run detect_storages
  [[ "${status}" -eq 1 ]]
}

@test "detect_storages: should return active storages from pvesm output" {
  local mock_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${mock_dir}"
  cat > "${mock_dir}/pvesm" <<'MOCK'
#!/usr/bin/env bash
cat <<'EOF'
Name         Type     Status           Total            Used       Available        %
local-lvm    lvmthin  active       114473984        5242880       109231104    4.58%
local        dir      active        30308696       18498408        10243340   61.03%
nfs-backup   nfs      inactive      50000000       10000000        40000000   20.00%
EOF
MOCK
  chmod +x "${mock_dir}/pvesm"
  PATH="${mock_dir}:${PATH}" run detect_storages
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"local-lvm"* ]]
  [[ "${output}" == *"local"* ]]
  [[ "${output}" != *"nfs-backup"* ]]
}

@test "prompt_menu: should work without labels" {
  fake_empty_input
  local OPTIONS=("x" "y")
  output=$(prompt_menu RESULT "Pick one:" "x" OPTIONS 2>&1)
  [[ "${output}" == *"[1] x (default)"* ]]
  [[ "${output}" == *"[2] y"* ]]
}
