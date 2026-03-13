#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
IMAGES_YML="${REPO_ROOT}/images.yml"

source "${SCRIPT_DIR}/lib/cloud-cfg.sh"

usage() {
  echo "Usage: $0 <codename> <arch> <variant>" >&2
  exit 1
}

if [[ $# -ne 3 ]]; then
  usage
fi

CODENAME="$1"
ARCH="$2"
VARIANT="$3"

# Resolve paths
BASE_CLOUD_CFG="${REPO_ROOT}/base/cloud.cfg"
VARIANT_CLOUD_CFG="${REPO_ROOT}/variants/${VARIANT}/cloud.cfg"
OUTPUT_FILE="ubuntu-${CODENAME}-${VARIANT}-${ARCH}.img"

# Validate base cloud.cfg
if [[ ! -f "${BASE_CLOUD_CFG}" ]]; then
  echo "Error: base/cloud.cfg not found at ${BASE_CLOUD_CFG}" >&2
  exit 1
fi

# Merge cloud-init configs
MERGED_CFG="$(merge_cloud_cfg "${IMAGES_YML}" "${VARIANT}" "${REPO_ROOT}")"
trap 'rm -f "${MERGED_CFG}"' EXIT

# Validate merged YAML
if ! yq eval '.' "${MERGED_CFG}" > /dev/null 2>&1; then
  echo "Error: Merged cloud.cfg is not valid YAML" >&2
  exit 1
fi

echo "Merged cloud.cfg:"
cat "${MERGED_CFG}"
echo ""

# Get download URL from images.yml
URL=$(yq eval ".bases[] | select(.codename == \"${CODENAME}\") | .url" "${IMAGES_YML}")
if [[ -z "${URL}" || "${URL}" == "null" ]]; then
  echo "Error: No URL found for codename '${CODENAME}' in images.yml" >&2
  exit 1
fi

# Replace {arch} placeholder
URL="${URL//\{arch\}/${ARCH}}"

echo "Downloading base image from ${URL}..."
wget -q --show-progress -O "${OUTPUT_FILE}" "${URL}"

echo "Injecting cloud.cfg into image..."
guestfish --rw -a "${OUTPUT_FILE}" -i upload "${MERGED_CFG}" /etc/cloud/cloud.cfg

echo "Built: ${OUTPUT_FILE}"
