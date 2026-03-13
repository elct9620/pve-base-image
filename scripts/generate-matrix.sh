#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGES_YML="${REPO_ROOT}/images.yml"

if [[ ! -f "${IMAGES_YML}" ]]; then
  echo "Error: images.yml not found at ${IMAGES_YML}" >&2
  exit 1
fi

if ! yq eval '.' "${IMAGES_YML}" > /dev/null 2>&1; then
  echo "Error: Failed to parse images.yml" >&2
  exit 1
fi

yq eval -o=json '[
  .bases[] as $base |
  $base.arch[] as $arch |
  .variants[] as $variant |
  {
    "codename": $base.codename,
    "version": $base.version,
    "arch": $arch,
    "variant": $variant.name,
    "display_name": $variant.display_name
  }
]' "${IMAGES_YML}" | jq -c '{"include": .}'
