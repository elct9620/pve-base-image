# PVE Base Image — Specification

## 1. Intent

### Purpose

Automate building customized Proxmox VE Cloud Images and provide a one-liner to import them as PVE Templates, eliminating the manual download-customize-import workflow.

### Users

Proxmox VE administrators (solo or small team) who need to quickly deploy VM Templates with pre-configured software.

### Impacts

- Eliminate repetitive work of downloading cloud images, editing cloud-init configs, and running `qm` commands to import
- Ensure all images share a consistent base configuration (e.g., qemu-guest-agent)
- Adding a new software variant requires only a single `cloud.cfg` file, with no need to understand the build pipeline

### Success Criteria

- After adding a base or variant entry to `images.yml`, CI automatically produces the corresponding image and uploads it to a GitHub Release
- Running `curl -fsSL https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh | bash` on a PVE host walks the user through an interactive menu to import a Template
- The resulting VM Template can be cloned via `qm clone` and initialized with cloud-init

### Non-goals

- Automatically detecting new upstream Ubuntu releases and updating `images.yml`
- Supporting operating systems other than Ubuntu (Debian, Rocky, etc.)
- cosign signature verification
- Providing a Web UI or API interface

---

## 2. Scope

### Features

| # | Feature | Description |
|---|---------|-------------|
| F1 | Image Build | GitHub Actions reads `images.yml`, builds a customized cloud image for each base × variant × arch combination, and uploads to GitHub Release |
| F2 | PVE Install Script | Interactive shell script that queries GitHub Releases, guides the user through image selection, downloads and imports as a PVE Template |

### User Journeys

#### J1: Add a Software Variant

- **Context**: An administrator needs a cloud image with Node.js pre-installed
- **Action**: Create `variants/nodejs/cloud.cfg`, add `nodejs` to the `variants` list in `images.yml`, push to main branch
- **Outcome**: CI automatically builds images with Node.js for all base × arch combinations and uploads them to a new GitHub Release

#### J2: Import a Template on PVE

- **Context**: An administrator wants to create a Docker Template on a PVE host
- **Action**: Run `curl -fsSL https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh | bash`, select architecture, base system, variant, and VM parameters in sequence
- **Outcome**: The script downloads the image, creates a VM, imports the disk, converts to Template, and displays `qm clone` usage

#### J3: Non-interactive Import

- **Context**: An administrator deploys Templates in batch via Ansible
- **Action**: Run `curl -fsSL https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh | VM_ID=9000 VARIANT=docker bash`
- **Outcome**: The script uses environment variables to skip interactive prompts and completes the Template import automatically

---

## 3. Behavior

### 3.1 Image Build Pipeline

#### images.yml Structure

```yaml
bases:
  - codename: <string>       # Ubuntu codename (e.g., jammy, noble)
    version: "<string>"       # Ubuntu version number (e.g., "22.04")
    url: <string>             # Download URL with {arch} placeholder
    arch: [<string>, ...]     # Supported architectures (amd64, arm64)

variants:
  - name: <string>            # Variant name; "base" must be listed explicitly
    display_name: <string>    # Human-readable name for manifest description (e.g., "Docker CE")
```

`base` must appear as an explicit entry in the `variants` list. It is not implicitly generated. When variant is `base`, the build uses `base/cloud.cfg` only and does not look for a `variants/base/` directory.

The `display_name` field is used to generate the `description` in `manifest.json`. For base variant, it is ignored — the description is always `"<OS> <version>"`. For other variants, the description is `"<OS> <version> + <display_name>"`.

#### Matrix Generation

`scripts/generate-matrix.sh` reads `images.yml` and produces the Cartesian product of `codename × arch × variant` as a GitHub Actions matrix JSON.

#### Build Prerequisites

- `yq` v4+ (uses `eval-all` syntax)
- `libguestfs-tools` (provides `guestfish`)
- `linux-image-generic` (required by libguestfs as a kernel source)
- Each matrix job builds a single image; parallel jobs do not share disk space

#### Architecture-specific Runners

- amd64 images are built on standard `ubuntu-latest` runners
- arm64 images are built on native arm64 runners (`ubuntu-24.04-arm`)
- No QEMU emulation is used; each architecture builds natively on its matching runner

#### Cloud-Init Config Merging

Uses `yq` to deep-merge base and variant `cloud.cfg` files:

- **variant is `base`**: Use `base/cloud.cfg` only
- **variant is not `base`**: Deep-merge `base/cloud.cfg` with `variants/<variant>/cloud.cfg`. Variant values override base values for the same keys; array fields are replaced (not appended)

The merged config is written into the image's `/etc/cloud/cloud.cfg` via `guestfish upload`.

#### Image Customization Method

Use `guestfish upload` (file injection) exclusively; do not use `virt-customize` (requires KVM). Package installation is deferred to cloud-init at first boot.

#### Release Asset Naming

```
<os>-<codename>-<variant>-<arch>.img
```

Example: `ubuntu-noble-docker-amd64.img`

#### Checksum Generation

Each Release includes a `checksums.sha256` file containing SHA256 hashes for all image assets. This file is generated after all images are built and uploaded alongside them as a Release asset.

#### Release Trigger

A GitHub Release is created on each push of a tag matching `v*` (e.g., `v2026.03.13.1`). Tags follow the format `v<YYYY>.<MM>.<DD>.<seq>`, where `<seq>` is a monotonically increasing integer starting from 1 for each date. This allows multiple releases on the same day. The workflow builds all matrix combinations and uploads assets to that Release.

#### manifest.json Contract

Each Release includes a `manifest.json` describing all images in the Release. This file is the contract between F1 (build) and F2 (install script).

```json
[
  {
    "file": "ubuntu-noble-docker-amd64.img",
    "os": "ubuntu",
    "codename": "noble",
    "version": "24.04",
    "variant": "docker",
    "arch": "amd64",
    "description": "Ubuntu 24.04 + Docker CE"
  }
]
```

| Field | Type | Description |
|-------|------|-------------|
| `file` | string | Asset filename, follows the naming convention pattern |
| `os` | string | Operating system (always `ubuntu` for now) |
| `codename` | string | Ubuntu release codename |
| `version` | string | Ubuntu version number |
| `variant` | string | Variant name |
| `arch` | string | CPU architecture |
| `description` | string | Auto-generated: `"<OS> <version>"` for base variant, `"<OS> <version> + <display_name>"` for other variants |

The install script depends on this schema to populate selection menus and construct download URLs.

### 3.2 PVE Install Script

#### Distribution

The install script is distributed via GitHub Raw Content from the `elct9620/pve-base-image` repository.

- **Canonical URL**: `https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh`
- This URL always points to the latest version on the `main` branch
- To pin a specific version, replace `main` with a tag (e.g., `v2026.03.13.1`) or a commit SHA

#### Prerequisites

- Must run as root
- Host must have `wget`, `jq`, and `qm`

The script checks these conditions at startup and exits with an error message if any are unmet.

#### Release Discovery

The script queries the GitHub Releases API for the latest release, then downloads `manifest.json` from that release's assets. If `GITHUB_TOKEN` is set, it is included in API requests to avoid rate limiting.

#### Interactive Flow

The script collects parameters in two phases: **image selection** (required choices) and **Template defaults** (optional, all have sensible defaults). Users press Enter to accept defaults, minimizing input for the common case.

**Phase 1 — Image Selection** (prompted with numbered menu):

| Order | Parameter | Default | Notes |
|-------|-----------|---------|-------|
| 1 | Architecture | amd64 | Options listed from manifest.json |
| 2 | Distribution | PVE version-dependent | PVE 8.x → noble, PVE 7.x → jammy |
| 3 | Variant | base | Options listed from manifest.json |

**Phase 2 — Template Defaults** (prompted with pre-filled defaults, Enter to accept all):

| Order | Parameter | Default | Notes |
|-------|-----------|---------|-------|
| 4 | VM ID | 9000 | Integer |
| 5 | VM name | `<os>-<codename>-<variant>` | Auto-generated from selections |
| 6 | Storage | local-lvm | PVE storage ID |
| 7 | Cloud-Init Storage | local-lvm | PVE storage ID |
| 8 | Memory | 2048 | MB; baked into Template as default, overridable at clone time |
| 9 | CPU cores | 1 | Integer; baked into Template as default, overridable at clone time |
| 10 | Network bridge | vmbr0 | PVE bridge name; baked into Template as default, overridable at clone time |

All Phase 2 parameters are baked into the Template as defaults. They can be overridden when cloning with `qm clone` + `qm set`, so the recommended workflow is to accept defaults here and customize per-VM at clone time.

In `curl | bash` mode, `read` reads from `/dev/tty`.

#### Non-interactive Mode

When a corresponding environment variable is set, the script skips that prompt:

| Environment Variable | Parameter |
|---------------------|-----------|
| `ARCH` | Architecture |
| `BASE` | Distribution codename |
| `VARIANT` | Variant |
| `VM_ID` | VM ID |
| `VM_NAME` | VM name |
| `STORAGE` | Storage |
| `CI_STORAGE` | Cloud-Init Storage |
| `MEMORY` | Memory |
| `CORES` | CPU cores |
| `BRIDGE` | Network bridge |

#### Checksum Verification

After downloading the image, the script also downloads `checksums.sha256` from the same Release and verifies the image's SHA256 checksum. If the checksum does not match, the script exits with an error before proceeding with Template creation.

#### Template Creation

The script downloads the selected image to a temp directory, then creates a PVE Template with the following properties:

| Property | Value |
|----------|-------|
| SCSI controller | VirtIO SCSI |
| Boot disk | Imported image attached as scsi0 |
| Cloud-init drive | Attached on the specified cloud-init storage |
| Serial console | Enabled (serial0) |
| Display | Serial terminal (vga = serial0) |
| Boot order | scsi0 |
| Memory, CPU, Network | As specified in Phase 2 parameters |

After configuration, the VM is converted to a Template. Temp files are cleaned up via `trap` on both normal and abnormal exit.

#### PVE Version Detection

Reads the PVE major version via `pveversion` to recommend a default distribution:

| PVE Version | Recommended Ubuntu |
|-------------|-------------------|
| 8.x | noble (24.04) |
| 7.x | jammy (22.04) |
| Undetectable | No recommendation shown; all options listed normally |

### 3.3 Error Scenarios

| Scenario | Behavior |
|----------|----------|
| **Build: base image download fails** | CI job fails, GitHub Actions reports the error, no Release is created |
| **Build: variant cloud.cfg not found** | When variant is `base`, no variant directory is needed; for other variants, the build script exits with an error if `cloud.cfg` is missing |
| **Build: yq merge produces invalid YAML** | Build script validates YAML after merging; exits on failure |
| **Build: images.yml is malformed or missing** | `generate-matrix.sh` exits with a non-zero code and prints a parse error; no matrix is generated and the workflow fails |
| **Install: not running as root** | Prints `Error: This script must be run as root` and exits with code 1 |
| **Install: missing jq or wget** | Prints the name of the missing tool and exits with code 1 |
| **Install: GitHub API request fails** | Prints an error message and suggests setting the `GITHUB_TOKEN` environment variable to avoid rate limiting |
| **Install: VM ID already exists** | Prints `Error: VM <ID> already exists` and exits without overwriting the existing VM |
| **Install: image download fails** | Prints an error message and exits; `trap` cleans up temp files |
| **Install: checksums.sha256 download fails** | Prints a warning and skips checksum verification; proceeds with Template creation |
| **Install: checksum mismatch** | Prints `Error: Checksum verification failed for <filename>` and exits with code 1; does not proceed with Template creation |
| **Install: qm command fails** | Prints `qm`'s error output and exits; does not attempt to roll back the created VM (user can manually run `qm destroy`) |
| **Install: manifest.json missing or malformed** | Prints `Error: Failed to parse manifest from release` and exits with code 1 |
| **Install: selected combination not in manifest** | Prints `Error: No image found for <codename>-<variant>-<arch>` and exits with code 1 |

---

## 4. Terminology

| Term | Definition |
|------|-----------|
| **base** | The upstream Ubuntu Cloud Image plus shared cloud-init config (e.g., qemu-guest-agent). The foundation layer for all variants |
| **variant** | A cloud-init config overlay on top of base that adds specific software (e.g., docker, nodejs, k3s). `base` itself is also a variant, meaning no additional software is overlaid |
| **codename** | Ubuntu release codename (e.g., jammy, noble), used in image naming and directory structure |
| **arch** | CPU architecture (amd64, arm64) |
| **Template** | A VM in PVE marked as a template. It cannot be started directly and can only be used via `qm clone` to create new VMs |
| **manifest.json** | A JSON file included in each GitHub Release that describes metadata for all images in that release |

## 5. Patterns

### Cloud-Init Config Merge Pattern

```
base/cloud.cfg  ×  variants/<variant>/cloud.cfg  →  merged.cfg  →  guestfish upload into image
```

All variants share the same merge rule: variant overrides base. Adding a new variant only requires creating `variants/<name>/cloud.cfg` — no changes to the build logic are needed.

### Naming Convention Pattern

All assets follow a uniform naming scheme based on `<os>-<codename>-<variant>`:

- Image assets: `<os>-<codename>-<variant>-<arch>.img`
- VM Template default name: `<os>-<codename>-<variant>`

This naming is used consistently across:
- GitHub Release asset filenames
- The `file` field in `manifest.json`
- The install script's download URL construction
- The install script's default VM Template name
