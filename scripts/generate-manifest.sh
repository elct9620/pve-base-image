#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGES_YML="${REPO_ROOT}/images.yml"

if [[ ! -f "${IMAGES_YML}" ]]; then
  echo "Error: images.yml not found at ${IMAGES_YML}" >&2
  exit 1
fi

yq eval -o=json '[
  .bases[] as $base |
  $base.arch[] as $arch |
  .variants[] as $variant |
  {
    "file": ("ubuntu-" + $base.codename + "-" + $variant.name + "-" + $arch + ".img"),
    "os": "ubuntu",
    "codename": $base.codename,
    "version": $base.version,
    "variant": $variant.name,
    "arch": $arch,
    "display_name": $variant.display_name
  }
]' "${IMAGES_YML}" | jq '[.[] | . + {
  "description": (if .variant == "base" then "Ubuntu " + .version else "Ubuntu " + .version + " + " + .display_name end)
} | del(.display_name)]'
