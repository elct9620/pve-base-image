# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PVE Base Image automates building customized Proxmox VE cloud images (Ubuntu-based) and provides an interactive install script to import them as PVE templates. Two main features:

- **F1 (Image Build):** GitHub Actions CI reads `images.yml`, builds images for all base × variant × architecture combinations, uploads to GitHub Releases
- **F2 (Install Script):** `install.sh` guides users through image selection and creates PVE templates via `qm` commands

## Build & Release

```bash
make version    # Show next version tag (e.g., v2026.03.14.1)
make release    # Create git tag and push (triggers CI build)
```

## Testing

Tests use [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
# Run all tests
bats test/

# Run individual test files
bats test/prompt.bats              # install.sh prompt functions
bats test/build.bats               # cloud config merging & validation
bats test/generate_matrix.bats     # GitHub Actions matrix generation
bats test/generate_manifest.bats   # manifest.json generation
```

CI runs prompt tests and script tests as separate jobs (see `.github/workflows/test.yml`).

## Architecture

### Configuration Layer

- `images.yml` — Central config defining Ubuntu bases (codename, version, URL, architectures) and variants (name, display_name, snippets)
- `base/cloud.cfg` — Base cloud-init config applied to all images (qemu-guest-agent, SSH hardening)
- `snippets/*.cfg` — Reusable cloud-init config blocks (e.g., `docker.cfg`)
- `variants/{name}/cloud.cfg` — Variant-specific cloud-init config

### Cloud Config Merge Order

Handled by `scripts/lib/cloud-cfg.sh` → `merge_cloud_cfg()`:

1. `base/cloud.cfg` (always applied)
2. Snippets from `images.yml` (in order)
3. `variants/{variant}/cloud.cfg` (if not base variant)

Uses `yq eval-all 'select(fileIndex==0) *+ select(fileIndex==1)'` for deep YAML merging. The merged config is injected into images at `/etc/cloud/cloud.cfg.d/99_pve.cfg`.

### Build Pipeline

- `scripts/generate-matrix.sh` — Produces GitHub Actions matrix JSON from `images.yml`
- `scripts/build.sh <codename> <arch> <variant>` — Builds a single image: merges cloud config, downloads Ubuntu cloud image, injects config via `guestfish`
- `scripts/generate-manifest.sh` — Produces `manifest.json` for install script consumption

### Install Script

`install.sh` is a standalone interactive script for PVE hosts. Key functions:
- `prompt VAR "msg" "default"` — Text input with default
- `prompt_menu VAR "msg" "default" ARRAY [LABELS]` — Menu selection
- Supports non-interactive mode via environment variables (`ARCH`, `BASE`, `VARIANT`, `VM_ID`, etc.)

## Known Constraints & Pitfalls

### Cloud-Init

- **Use drop-in files, never overwrite cloud.cfg:** Custom config must go to `/etc/cloud/cloud.cfg.d/99_pve.cfg`. Overwriting `/etc/cloud/cloud.cfg` destroys the original module lists and system_info, breaking SSH key injection, user creation, etc.
- **runcmd executes under /bin/sh (dash), not bash:** Avoid bash-only syntax (e.g., `eval "$(tool activate bash)"`). Use POSIX-compatible commands or write bash scripts to profile.d instead.
- **PVE template requires `--agent enabled=1`:** Installing qemu-guest-agent via cloud.cfg is not enough. The VM config must include `--agent enabled=1` for PVE to communicate with the guest agent (IP reporting, graceful shutdown).

### yq / jq

- **Use `*+` for array merging in yq:** The `*` operator overwrites arrays instead of concatenating. This causes base/snippet `packages`/`runcmd` entries to be silently lost. Always use `*+`.
- **yq v4 does not support if/then/else:** Conditional logic is a jq-only feature. Convert YAML to JSON with yq first, then apply conditionals in jq.

### CI / libguestfs

- **libguestfs must use direct backend:** The default libvirt backend fails on GitHub Actions runners. Set `LIBGUESTFS_BACKEND=direct` for all architectures.
- **Ubuntu kernel file permissions:** `/boot/vmlinuz-*` defaults to root-only (0600). supermin requires read access, so CI must adjust permissions.
- **Use guestfish, not virt-edit:** `virt-edit --upload` is not supported. Use `guestfish upload` for file injection.

### mise (Coding Variant)

- **System config must be `/etc/mise/config.toml`:** `mise activate` only searches default paths (`~/.config/mise/`, `/etc/mise/`). Writing to `/etc/mise.toml` makes tools invisible to login shells.
- **`chmod -R a+rX` must run after all installs:** Running chmod before `npm install -g` leaves newly installed binaries and reshimmed shims without read/execute permissions for non-root users. Always place chmod as the final step.
- **`mise exec` must specify tool@version:** Bare `mise exec --` without a tool spec (e.g., `node@lts`) may fail to resolve binaries in runcmd context where PATH is minimal.

### install.sh Compatibility

- **Pipe mode (`curl | bash`):** `BASH_SOURCE` is unset in pipe mode, causing `set -u` to abort. Use `${BASH_SOURCE:-}` as a default. `return` also fails outside sourced context, so the source guard needs special handling.

### Ubuntu Images

- **Not all architectures have minimal images:** For example, Jammy (22.04) minimal cloud images have no arm64 build. Verify the download URL actually exists when adding a new base.

## Key Tools

| Tool | Purpose |
|------|---------|
| `yq` (v4.45.4+) | YAML parsing & deep merging |
| `jq` | JSON processing |
| `guestfish` (libguestfs) | Cloud image file injection |
| `bats` | Shell script testing |

## Adding New Content

**New variant:** Create `variants/{name}/cloud.cfg`, add entry to `images.yml` under `variants` (optionally referencing snippets).

**New base:** Add entry to `images.yml` under `bases` with codename, version, URL (with `{arch}` placeholder), and supported architectures.

**New snippet:** Create `snippets/{name}.cfg`, reference it in variant entries in `images.yml`.
