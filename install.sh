#!/usr/bin/env bash

# --- Helper functions ---

: "${TTY_INPUT:=/dev/tty}"

info() { echo "==> $*"; }
error() { echo "Error: $*" >&2; exit 1; }

prompt() {
  local var="$1" prompt_msg="$2" default="$3"
  if [[ -n "${!var:-}" ]]; then
    return
  fi
  local input
  read -r -p "${prompt_msg} [${default}]: " input <"${TTY_INPUT}" || true
  if [[ -z "${input}" ]]; then
    printf -v "${var}" '%s' "${default}"
  else
    printf -v "${var}" '%s' "${input}"
  fi
}

prompt_menu() {
  local var="$1" prompt_msg="$2" default="$3"
  shift 3

  local options=() labels=()
  local separator_found=false
  for arg in "$@"; do
    if [[ "${arg}" == "--" ]]; then
      separator_found=true
      continue
    fi
    if [[ "${separator_found}" == true ]]; then
      labels+=("${arg}")
    else
      options+=("${arg}")
    fi
  done

  if [[ -n "${!var:-}" ]]; then
    return
  fi

  local display marker
  echo ""
  echo "${prompt_msg}"
  local i=1
  for idx in "${!options[@]}"; do
    display="${options[${idx}]}"
    if [[ ${#labels[@]} -gt 0 ]]; then
      display="${labels[${idx}]}"
    fi
    marker=""
    if [[ "${options[${idx}]}" == "${default}" ]]; then
      marker=" (default)"
    fi
    echo "  [${i}] ${display}${marker}"
    i=$((i + 1))
  done

  local input
  read -r -p "Select [1-${#options[@]}]: " input <"${TTY_INPUT}" || true

  if [[ -z "${input}" ]]; then
    printf -v "${var}" '%s' "${default}"
  elif [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 1 && input <= ${#options[@]} )); then
    printf -v "${var}" '%s' "${options[$((input - 1))]}"
  else
    error "Invalid selection: ${input}"
  fi
}

# --- Main (skipped when sourced for testing) ---

[[ "${BASH_SOURCE[0]}" != "${0}" ]] && return 0

set -euo pipefail

REPO="elct9620/pve-base-image"

# --- Prerequisites ---

if [[ "$(id -u)" -ne 0 ]]; then
  error "This script must be run as root"
fi

for cmd in wget jq qm; do
  if ! command -v "${cmd}" > /dev/null 2>&1; then
    error "Required command not found: ${cmd}"
  fi
done

# --- Temp directory with cleanup ---

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

# --- GitHub API helpers ---

gh_api() {
  local url="$1"
  local -a headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers+=("--header" "Authorization: Bearer ${GITHUB_TOKEN}")
  fi
  headers+=("--header" "Accept: application/vnd.github+json")

  local response
  if ! response=$(wget -qO- "${headers[@]}" "${url}" 2>/dev/null); then
    echo "Error: GitHub API request failed for ${url}" >&2
    echo "If you are being rate limited, set the GITHUB_TOKEN environment variable." >&2
    exit 1
  fi
  echo "${response}"
}

# --- Release Discovery ---

info "Fetching latest release..."
RELEASE_JSON=$(gh_api "https://api.github.com/repos/${REPO}/releases/latest")
TAG_NAME=$(echo "${RELEASE_JSON}" | jq -r '.tag_name')
info "Found release: ${TAG_NAME}"

# Download manifest.json
MANIFEST_URL=$(echo "${RELEASE_JSON}" | jq -r '.assets[] | select(.name == "manifest.json") | .browser_download_url')
if [[ -z "${MANIFEST_URL}" || "${MANIFEST_URL}" == "null" ]]; then
  error "Failed to parse manifest from release"
fi

MANIFEST="${TMPDIR}/manifest.json"
if ! wget -qO "${MANIFEST}" "${MANIFEST_URL}"; then
  error "Failed to parse manifest from release"
fi

if ! jq '.' "${MANIFEST}" > /dev/null 2>&1; then
  error "Failed to parse manifest from release"
fi

# --- PVE Version Detection ---

DEFAULT_BASE="noble"
if command -v pveversion > /dev/null 2>&1; then
  PVE_MAJOR=$(pveversion | sed -n 's/.*pve-manager\/\([0-9]*\).*/\1/p' || true)
  case "${PVE_MAJOR}" in
    8) DEFAULT_BASE="noble" ;;
    7) DEFAULT_BASE="jammy" ;;
  esac
fi

# --- Phase 1: Image Selection ---

info "Phase 1: Image Selection"

# Architecture
mapfile -t ARCH_OPTIONS < <(jq -r '[.[].arch] | unique | .[]' "${MANIFEST}")
prompt_menu ARCH "Select architecture:" "amd64" "${ARCH_OPTIONS[@]}"

# Distribution
mapfile -t DIST_OPTIONS < <(jq -r --arg arch "${ARCH}" '[.[] | select(.arch == $arch)] | [.[].codename] | unique | .[]' "${MANIFEST}")
DIST_LABELS=()
for dist in "${DIST_OPTIONS[@]}"; do
  ver=$(jq -r --arg c "${dist}" '[.[] | select(.codename == $c)][0].version' "${MANIFEST}")
  DIST_LABELS+=("${dist} (${ver})")
done

prompt_menu BASE "Select distribution:" "${DEFAULT_BASE}" "${DIST_OPTIONS[@]}" -- "${DIST_LABELS[@]}"

# Variant
mapfile -t VARIANT_OPTIONS < <(jq -r --arg arch "${ARCH}" --arg base "${BASE}" \
  '[.[] | select(.arch == $arch and .codename == $base)] | [.[].variant] | unique | .[]' "${MANIFEST}")
prompt_menu VARIANT "Select variant:" "base" "${VARIANT_OPTIONS[@]}"

# Validate selection exists in manifest
SELECTED=$(jq -r --arg arch "${ARCH}" --arg base "${BASE}" --arg variant "${VARIANT}" \
  '.[] | select(.arch == $arch and .codename == $base and .variant == $variant)' "${MANIFEST}")
if [[ -z "${SELECTED}" ]]; then
  error "No image found for ${BASE}-${VARIANT}-${ARCH}"
fi

IMAGE_FILE=$(echo "${SELECTED}" | jq -r '.file')
DESCRIPTION=$(echo "${SELECTED}" | jq -r '.description')
info "Selected: ${DESCRIPTION} (${IMAGE_FILE})"

# --- Phase 2: Template Parameters ---

info "Phase 2: Template Parameters"

DEFAULT_VM_NAME="cloud-${BASE}-${VARIANT}"

prompt VM_ID "VM ID" "9000"
prompt VM_NAME "VM name" "${DEFAULT_VM_NAME}"
prompt STORAGE "Storage" "local-lvm"
prompt CI_STORAGE "Cloud-Init storage" "local-lvm"
prompt MEMORY "Memory (MB)" "2048"
prompt CORES "CPU cores" "1"
prompt BRIDGE "Network bridge" "vmbr0"

# --- Validate VM ID ---

if qm status "${VM_ID}" > /dev/null 2>&1; then
  error "VM ${VM_ID} already exists"
fi

# --- Download Image ---

DOWNLOAD_BASE_URL=$(echo "${RELEASE_JSON}" | jq -r '.assets[] | select(.name == "'"${IMAGE_FILE}"'") | .browser_download_url')
if [[ -z "${DOWNLOAD_BASE_URL}" || "${DOWNLOAD_BASE_URL}" == "null" ]]; then
  error "Image asset ${IMAGE_FILE} not found in release"
fi

IMAGE_PATH="${TMPDIR}/${IMAGE_FILE}"
info "Downloading ${IMAGE_FILE}..."
if ! wget -q --show-progress -O "${IMAGE_PATH}" "${DOWNLOAD_BASE_URL}"; then
  error "Failed to download image"
fi

# --- Checksum Verification ---

CHECKSUMS_URL=$(echo "${RELEASE_JSON}" | jq -r '.assets[] | select(.name == "checksums.sha256") | .browser_download_url')
if [[ -n "${CHECKSUMS_URL}" && "${CHECKSUMS_URL}" != "null" ]]; then
  CHECKSUMS_PATH="${TMPDIR}/checksums.sha256"
  if wget -qO "${CHECKSUMS_PATH}" "${CHECKSUMS_URL}" 2>/dev/null; then
    info "Verifying checksum..."
    EXPECTED=$(grep "${IMAGE_FILE}" "${CHECKSUMS_PATH}" | awk '{print $1}')
    ACTUAL=$(sha256sum "${IMAGE_PATH}" | awk '{print $1}')
    if [[ "${EXPECTED}" != "${ACTUAL}" ]]; then
      error "Checksum verification failed for ${IMAGE_FILE}"
    fi
    info "Checksum verified."
  else
    echo "Warning: Could not download checksums.sha256, skipping verification." >&2
  fi
else
  echo "Warning: checksums.sha256 not found in release, skipping verification." >&2
fi

# --- Template Creation ---

info "Creating VM ${VM_ID}..."
qm create "${VM_ID}" \
  --name "${VM_NAME}" \
  --memory "${MEMORY}" \
  --cores "${CORES}" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --scsihw virtio-scsi-pci \
  --serial0 socket \
  --vga serial0

info "Importing disk to ${STORAGE}..."
qm importdisk "${VM_ID}" "${IMAGE_PATH}" "${STORAGE}"

info "Configuring VM..."
qm set "${VM_ID}" \
  --scsi0 "${STORAGE}:vm-${VM_ID}-disk-0" \
  --boot order=scsi0 \
  --ide2 "${CI_STORAGE}:cloudinit"

info "Converting to template..."
qm template "${VM_ID}"

echo ""
info "Template created successfully!"
echo ""
echo "Usage:"
echo "  qm clone ${VM_ID} <new-vm-id> --name <name>"
echo "  qm set <new-vm-id> --ciuser admin --cipassword secret --ipconfig0 ip=dhcp"
echo "  qm start <new-vm-id>"
