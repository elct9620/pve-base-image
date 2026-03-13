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
    "description": (
      if $variant.name == "base" then
        "Ubuntu " + $base.version
      else
        "Ubuntu " + $base.version + " + " + $variant.display_name
      end
    )
  }
]' "${IMAGES_YML}" | jq '.'
