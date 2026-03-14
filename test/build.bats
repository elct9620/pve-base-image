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

@test "build: coding variant merged runcmd should contain base, snippet, and variant commands" {
  local merged
  merged="$(merge_cloud_cfg "${IMAGES_YML}" "coding" "${REPO_ROOT}")"
  MERGED_FILES+=("${merged}")

  local runcmd
  runcmd=$(yq eval '.runcmd[]' "${merged}")

  # Base: qemu-guest-agent
  echo "${runcmd}" | grep -q 'qemu-guest-agent'
  # Snippet (docker): docker-ce
  echo "${runcmd}" | grep -q 'docker-ce'
  # Variant (coding): mise
  echo "${runcmd}" | grep -q 'mise'
}

@test "build: docker variant merged runcmd should contain base qemu-guest-agent command" {
  local merged
  merged="$(merge_cloud_cfg "${IMAGES_YML}" "docker" "${REPO_ROOT}")"
  MERGED_FILES+=("${merged}")

  local runcmd
  runcmd=$(yq eval '.runcmd[]' "${merged}")

  # Base: qemu-guest-agent
  echo "${runcmd}" | grep -q 'qemu-guest-agent'
  # Snippet (docker): docker-ce
  echo "${runcmd}" | grep -q 'docker-ce'
}

@test "build: coding variant runcmd should not call mise activate directly (only in profile.d)" {
  local merged
  merged="$(merge_cloud_cfg "${IMAGES_YML}" "coding" "${REPO_ROOT}")"
  MERGED_FILES+=("${merged}")

  # runcmd items containing "mise activate" must also contain "profile.d" (heredoc context)
  local non_profile_activate
  non_profile_activate=$(yq eval '.runcmd[] | select(test("mise activate")) | select(test("profile.d") | not)' "${merged}" || true)

  [[ -z "${non_profile_activate}" ]]
}

@test "build: coding variant mise exec should specify explicit tool version" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  # Every 'mise exec' call must include a tool@version spec (e.g. node@lts)
  local bare_exec
  bare_exec=$(grep 'mise exec' "${variant_cfg}" | grep -v 'mise exec [a-z].*@' || true)

  [[ -z "${bare_exec}" ]]
}

@test "build: coding variant mise config should use /etc/mise/config.toml" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  # Should use /etc/mise/config.toml (system-level config directory)
  run grep '/etc/mise.toml' "${variant_cfg}"
  [[ "${status}" -ne 0 ]]

  run grep '/etc/mise/config.toml' "${variant_cfg}"
  [[ "${status}" -eq 0 ]]
}

@test "build: coding variant chmod should run after npm install" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  # Find line numbers for npm install and chmod
  local npm_line chmod_line
  npm_line=$(grep -n 'npm install -g' "${variant_cfg}" | head -1 | cut -d: -f1)
  chmod_line=$(grep -n 'chmod -R a+rX /usr/local/share/mise' "${variant_cfg}" | head -1 | cut -d: -f1)

  # chmod must appear after npm install
  [[ -n "${npm_line}" ]]
  [[ -n "${chmod_line}" ]]
  [[ "${chmod_line}" -gt "${npm_line}" ]]
}

@test "build: coding variant profile.d should not set MISE_DATA_DIR" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  # profile.d scripts must not export MISE_DATA_DIR (causes permission issues for non-root users)
  local profile_data_dir
  profile_data_dir=$(grep -A5 'profile.d/mise' "${variant_cfg}" | grep 'MISE_DATA_DIR' || true)

  [[ -z "${profile_data_dir}" ]]
}

@test "build: coding variant profile.d should set MISE_SHARED_INSTALL_DIRS" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  run grep 'MISE_SHARED_INSTALL_DIRS' "${variant_cfg}"
  [[ "${status}" -eq 0 ]]
}

@test "build: coding variant profile.d should set NPM_CONFIG_PREFIX" {
  local variant_cfg="${REPO_ROOT}/variants/coding/cloud.cfg"

  run grep 'NPM_CONFIG_PREFIX' "${variant_cfg}"
  [[ "${status}" -eq 0 ]]
}

@test "build: snippet files referenced in images.yml should exist" {
  local snippets
  snippets=$(yq eval '.variants[].snippets[]' "${IMAGES_YML}" 2>/dev/null | sort -u || true)

  for snippet in ${snippets}; do
    [[ -f "${REPO_ROOT}/snippets/${snippet}.cfg" ]]
  done
}
