#!/usr/bin/env bats

setup() {
  SCRIPT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)/scripts/generate-manifest.sh"
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "generate-manifest: should output valid JSON" {
  output=$(bash "${SCRIPT}")
  echo "${output}" | jq '.' > /dev/null 2>&1
}

@test "generate-manifest: should contain required fields in each entry" {
  output=$(bash "${SCRIPT}")
  missing=$(echo "${output}" | jq '[.[] | select(
    (.file | length) == 0 or
    (.os | length) == 0 or
    (.codename | length) == 0 or
    (.version | length) == 0 or
    (.variant | length) == 0 or
    (.arch | length) == 0 or
    (.description | length) == 0
  )] | length')
  [[ "${missing}" -eq 0 ]]
}

@test "generate-manifest: should produce entries matching images.yml" {
  output=$(bash "${SCRIPT}")
  count=$(echo "${output}" | jq 'length')
  expected=$(yq eval '[.bases[] as $base | $base.arch[] as $arch | .variants[] as $variant | 1] | length' "${REPO_ROOT}/images.yml")
  [[ "${count}" -eq "${expected}" ]]
}

@test "generate-manifest: should set description to 'Ubuntu {version}' for base variant" {
  output=$(bash "${SCRIPT}")
  base_entries=$(echo "${output}" | jq '[.[] | select(.variant == "base")]')
  bad=$(echo "${base_entries}" | jq '[.[] | select(.description != ("Ubuntu " + .version))] | length')
  [[ "${bad}" -eq 0 ]]
}

@test "generate-manifest: should set description to 'Ubuntu {version} + {display_name}' for non-base variant" {
  output=$(bash "${SCRIPT}")
  non_base=$(echo "${output}" | jq '[.[] | select(.variant != "base")]')
  count=$(echo "${non_base}" | jq 'length')
  # Ensure there are non-base entries to test
  [[ "${count}" -gt 0 ]]
  # Description should contain ' + ' for non-base variants
  bad=$(echo "${non_base}" | jq '[.[] | select(.description | test(" \\+ ") | not)] | length')
  [[ "${bad}" -eq 0 ]]
}

@test "generate-manifest: should fail when images.yml is missing" {
  local tmpdir
  tmpdir="$(mktemp -d)"
  cp "${SCRIPT}" "${tmpdir}/generate-manifest.sh"
  run bash "${tmpdir}/generate-manifest.sh"
  rm -rf "${tmpdir}"
  [[ "${status}" -ne 0 ]]
  [[ "${output}" == *"images.yml not found"* ]]
}
