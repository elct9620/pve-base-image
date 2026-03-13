#!/usr/bin/env bats

setup() {
  SCRIPT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/scripts/generate-matrix.sh"
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "generate-matrix: should output valid JSON" {
  output=$(bash "${SCRIPT}")
  echo "${output}" | jq '.' > /dev/null 2>&1
}

@test "generate-matrix: should contain include key" {
  output=$(bash "${SCRIPT}")
  result=$(echo "${output}" | jq -r 'has("include")')
  [[ "${result}" == "true" ]]
}

@test "generate-matrix: should contain required fields in each entry" {
  output=$(bash "${SCRIPT}")
  missing=$(echo "${output}" | jq '[.include[] | select(
    (.codename | length) == 0 or
    (.version | length) == 0 or
    (.arch | length) == 0 or
    (.variant | length) == 0
  )] | length')
  [[ "${missing}" -eq 0 ]]
}

@test "generate-matrix: should produce entries matching images.yml" {
  output=$(bash "${SCRIPT}")
  count=$(echo "${output}" | jq '.include | length')
  # expected count is dynamically calculated from images.yml
  expected=$(yq eval '[.bases[] as $base | $base.arch[] as $arch | .variants[] as $variant | 1] | length' "${REPO_ROOT}/images.yml")
  [[ "${count}" -eq "${expected}" ]]
}

@test "generate-matrix: should fail when images.yml is missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cp "${SCRIPT}" "${tmpdir}/generate-matrix.sh"
  run bash "${tmpdir}/generate-matrix.sh"
  rm -rf "${tmpdir}"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"images.yml not found"* ]]
}
