#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  IMAGES_YML="${REPO_ROOT}/images.yml"
  BASE_CLOUD_CFG="${REPO_ROOT}/base/cloud.cfg"

  source "${REPO_ROOT}/scripts/lib/cloud-cfg.sh"

  MERGED_FILES=()
}

teardown() {
  for f in "${MERGED_FILES[@]}"; do
    rm -f "$f"
  done
}

@test "build: all non-base variant cloud.cfg should merge with base as valid YAML" {
  local variants
  variants=$(yq eval '.variants[] | select(.name != "base") | .name' "${IMAGES_YML}")

  for variant in ${variants}; do
    local merged
    merged="$(merge_cloud_cfg "${IMAGES_YML}" "${variant}" "${REPO_ROOT}")"
    MERGED_FILES+=("${merged}")

    run yq eval '.' "${merged}"
    [[ "${status}" -eq 0 ]]
  done
}

@test "build: merged config should contain packages and runcmd" {
  local variants
  variants=$(yq eval '.variants[] | select(.name != "base") | .name' "${IMAGES_YML}")

  for variant in ${variants}; do
    local merged
    merged="$(merge_cloud_cfg "${IMAGES_YML}" "${variant}" "${REPO_ROOT}")"
    MERGED_FILES+=("${merged}")

    local has_packages has_runcmd
    has_packages=$(yq eval 'has("packages")' "${merged}")
    has_runcmd=$(yq eval 'has("runcmd")' "${merged}")

    [[ "${has_packages}" == "true" ]]
    [[ "${has_runcmd}" == "true" ]]
  done
}

@test "merge_cloud_cfg should fail when snippet file is missing" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  # Create minimal repo structure with base cloud.cfg
  mkdir -p "${tmp_dir}/base"
  echo "packages: []" > "${tmp_dir}/base/cloud.cfg"

  # Create images.yml referencing a non-existent snippet
  cat > "${tmp_dir}/images.yml" <<'YAML'
variants:
  - name: test
    snippets:
      - nonexistent
YAML

  run merge_cloud_cfg "${tmp_dir}/images.yml" "test" "${tmp_dir}"
  rm -rf "${tmp_dir}"

  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"snippets/nonexistent.cfg not found"* ]]
}

@test "merge_cloud_cfg should fail when base cloud.cfg is missing" {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  # Create images.yml but no base/cloud.cfg
  cat > "${tmp_dir}/images.yml" <<'YAML'
variants:
  - name: test
    snippets: []
YAML

  run merge_cloud_cfg "${tmp_dir}/images.yml" "test" "${tmp_dir}"
  rm -rf "${tmp_dir}"

  [[ "${status}" -eq 1 ]]
  [[ "${output}" == *"base/cloud.cfg not found"* ]]
}

@test "build: guestfish should upload to cloud.cfg.d drop-in, not overwrite cloud.cfg" {
  run grep -E 'guestfish.*upload' "${REPO_ROOT}/scripts/build.sh"
  [[ "${status}" -eq 0 ]]
  [[ "${output}" == *"/etc/cloud/cloud.cfg.d/99_pve.cfg"* ]]
  [[ "${output}" != *"upload\"*\"/etc/cloud/cloud.cfg\""* ]]
}

@test "build: snippet files referenced in images.yml should exist" {
  local snippets
  snippets=$(yq eval '.variants[].snippets[]' "${IMAGES_YML}" 2>/dev/null | sort -u || true)

  for snippet in ${snippets}; do
    [[ -f "${REPO_ROOT}/snippets/${snippet}.cfg" ]]
  done
}
