#!/usr/bin/env bash

# merge_cloud_cfg <images_yml> <variant> <repo_root>
# Merges base → snippets → variant cloud.cfg
# Outputs merged cloud.cfg temp file path to stdout
# Caller is responsible for cleaning up the temp file
merge_cloud_cfg() {
  local images_yml="$1" variant="$2" repo_root="$3"
  local base_cfg="${repo_root}/base/cloud.cfg"
  local variant_cfg="${repo_root}/variants/${variant}/cloud.cfg"
  local merged
  merged="$(mktemp)"

  if [[ ! -f "${base_cfg}" ]]; then
    echo "Error: base/cloud.cfg not found at ${base_cfg}" >&2
    rm -f "${merged}"
    return 1
  fi

  cp "${base_cfg}" "${merged}"

  # Merge snippets in order
  local snippets
  snippets=$(yq eval ".variants[] | select(.name == \"${variant}\") | .snippets[]" "${images_yml}" 2>/dev/null || true)
  for snippet in ${snippets}; do
    local snippet_cfg="${repo_root}/snippets/${snippet}.cfg"
    if [[ ! -f "${snippet_cfg}" ]]; then
      echo "Error: snippets/${snippet}.cfg not found" >&2
      rm -f "${merged}"
      return 1
    fi
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
      "${merged}" "${snippet_cfg}" > "${merged}.tmp"
    mv "${merged}.tmp" "${merged}"
  done

  # Merge variant cloud.cfg if exists (non-base variants may have additional config)
  if [[ "${variant}" != "base" ]] && [[ -f "${variant_cfg}" ]]; then
    yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' \
      "${merged}" "${variant_cfg}" > "${merged}.tmp"
    mv "${merged}.tmp" "${merged}"
  fi

  echo "${merged}"
}
