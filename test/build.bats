#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  IMAGES_YML="${REPO_ROOT}/images.yml"
  BASE_CLOUD_CFG="${REPO_ROOT}/base/cloud.cfg"
}

@test "build: all non-base variant cloud.cfg should merge with base as valid YAML" {
  local variants
  variants=$(yq eval '.variants[] | select(.name != "base") | .name' "${IMAGES_YML}")

  for variant in ${variants}; do
    local merged
    merged="$(mktemp)"

    # Start with base
    cp "${BASE_CLOUD_CFG}" "${merged}"

    # Merge snippets
    local snippets
    snippets=$(yq eval ".variants[] | select(.name == \"${variant}\") | .snippets[]" "${IMAGES_YML}" 2>/dev/null || true)
    for snippet in ${snippets}; do
      local snippet_cfg="${REPO_ROOT}/snippets/${snippet}.cfg"
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "${merged}" "${snippet_cfg}" > "${merged}.tmp"
      mv "${merged}.tmp" "${merged}"
    done

    # Merge variant cloud.cfg if exists
    local variant_cfg="${REPO_ROOT}/variants/${variant}/cloud.cfg"
    if [[ -f "${variant_cfg}" ]]; then
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "${merged}" "${variant_cfg}" > "${merged}.tmp"
      mv "${merged}.tmp" "${merged}"
    fi

    # Validate merged YAML
    run yq eval '.' "${merged}"
    rm -f "${merged}"
    [[ "${status}" -eq 0 ]]
  done
}

@test "build: merged config should contain packages and runcmd" {
  local variants
  variants=$(yq eval '.variants[] | select(.name != "base") | .name' "${IMAGES_YML}")

  for variant in ${variants}; do
    local merged
    merged="$(mktemp)"

    # Start with base
    cp "${BASE_CLOUD_CFG}" "${merged}"

    # Merge snippets
    local snippets
    snippets=$(yq eval ".variants[] | select(.name == \"${variant}\") | .snippets[]" "${IMAGES_YML}" 2>/dev/null || true)
    for snippet in ${snippets}; do
      local snippet_cfg="${REPO_ROOT}/snippets/${snippet}.cfg"
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "${merged}" "${snippet_cfg}" > "${merged}.tmp"
      mv "${merged}.tmp" "${merged}"
    done

    # Merge variant cloud.cfg if exists
    local variant_cfg="${REPO_ROOT}/variants/${variant}/cloud.cfg"
    if [[ -f "${variant_cfg}" ]]; then
      yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
        "${merged}" "${variant_cfg}" > "${merged}.tmp"
      mv "${merged}.tmp" "${merged}"
    fi

    # Check packages and runcmd keys exist
    local has_packages has_runcmd
    has_packages=$(yq eval 'has("packages")' "${merged}")
    has_runcmd=$(yq eval 'has("runcmd")' "${merged}")
    rm -f "${merged}"

    [[ "${has_packages}" == "true" ]]
    [[ "${has_runcmd}" == "true" ]]
  done
}

@test "build: snippet files referenced in images.yml should exist" {
  local snippets
  snippets=$(yq eval '.variants[].snippets[]' "${IMAGES_YML}" 2>/dev/null | sort -u || true)

  for snippet in ${snippets}; do
    [[ -f "${REPO_ROOT}/snippets/${snippet}.cfg" ]]
  done
}
