# PVE Base Image

Automate building customized Proxmox VE Cloud Images (based on Ubuntu minimal cloud images) and provide a one-liner to import them as PVE Templates.

```
                    ┌─────────────────────────────────────────────┐
                    │              GitHub Actions CI              │
                    │                                             │
  images.yml ──────►│  base/cloud.cfg ─┐                          │
                    │                  ├─ yq merge ─► virt-edit ──┼──► GitHub Release
  variants/         │  variants/       │                          │      ├─ *.img
  └─ docker/  ─────►│  └─ cloud.cfg ───┘                          │      ├─ manifest.json
  └─ coding/       │                                             │      └─ checksums.sha256
                    │  snippets/                                  │
  snippets/  ──────►│  └─ docker.cfg   (reusable config blocks)  │
                    └─────────────────────────────────────────────┘
                                                                          │
                    ┌─────────────────────────────────────────────┐         │
                    │              PVE Host                       │         │
                    │                                             │    download
                    │  curl | bash ──► select image ──► qm import │◄────────┘
                    │                                             │
                    │  Result: VM Template (qm clone to use)      │
                    └─────────────────────────────────────────────┘
```

## Quick Start

### Import a Template on PVE

Run on your Proxmox VE host as root:

```bash
curl -fsSL https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh | bash
```

The script will guide you through:

1. **Architecture** — amd64 or arm64
2. **Distribution** — Ubuntu codename (e.g., noble, jammy)
3. **Variant** — base, docker, coding
4. **Template parameters** — VM ID, storage (auto-detected), memory, CPU, network
5. **Cloud-Init defaults** — DHCP configuration

```
┌─── Phase 1: Image Selection ───────────────────────────┐
│                                                        │
│  Architecture?   [1] amd64  [2] arm64                  │
│  Distribution?   [1] noble (24.04)  [2] jammy (22.04)  │
│  Variant?        [1] base  [2] docker  [3] coding      │
│                                                        │
├─── Phase 2: Template Parameters ───────────────────────┤
│                                                        │
│  VM ID?          9000                                  │
│  VM Name?        ubuntu-noble-docker                   │
│  Storage?        [1] local-lvm  [2] ceph  (auto-detected) │
│  CI Storage?     [1] local-lvm  [2] ceph  (auto-detected) │
│  Memory?         2048 MB                               │
│  CPU Cores?      1                                     │
│  Network?        vmbr0                                 │
│                                                        │
├─── Phase 3: Cloud-Init Defaults ───────────────────────┤
│                                                        │
│  Enable DHCP?    [y] (default)                         │
│                                                        │
└────────────────────────────────────────────────────────┘
```

Storage is auto-detected from PVE when `pvesm` is available. If auto-detection fails, you will be prompted to enter storage names manually.

After completion, clone the template to create VMs:

```bash
qm clone 9000 100 --name my-vm
qm set 100 --ciuser admin --sshkeys ~/.ssh/authorized_keys
qm start 100
```

### Non-interactive Mode

Use environment variables to skip prompts, useful for Ansible or batch deployments:

```bash
curl -fsSL https://raw.githubusercontent.com/elct9620/pve-base-image/main/install.sh | VM_ID=9000 VARIANT=docker bash
```

## Add a New Variant

> **Using [Claude Code](https://claude.ai/code)?** Run `/variants` to create a new variant interactively. The skill guides you through naming, package research, snippet reuse, and config generation — no manual steps required.

### 1. Create a variant directory with a `cloud.cfg`

Each variant has its own directory under `variants/` containing a `cloud.cfg` file with cloud-init configuration:

```bash
mkdir -p variants/my-variant
cat > variants/my-variant/cloud.cfg <<'EOF'
packages:
  - my-package

runcmd:
  - echo "Custom setup commands here"
EOF
```

The variant's `cloud.cfg` is merged on top of the base `cloud.cfg` during the build.

### 2. (Optional) Use snippets for shared configuration

The `snippets/` directory contains reusable cloud-init config blocks (e.g., `snippets/docker.cfg`). Variants can reference snippets in `images.yml` to compose configurations without duplication. For example, both `docker` and `coding` variants reuse the `docker` snippet.

### 3. Register the variant in `images.yml`

```yaml
variants:
  - name: base
    display_name: ""
  - name: docker
    display_name: "Docker CE"
    snippets:
      - docker
  - name: my-variant
    display_name: "My Variant"
    snippets:
      - docker          # optional: reuse existing snippets
```

### 4. Tag a release

Use `make release` to create a date-based version tag (`v<YYYY>.<MM>.<DD>.<seq>`) and push it:

```bash
git push origin main
make release
```

CI automatically builds images for all `codename × arch × variant` combinations and uploads them to the GitHub Release.

```
images.yml                variants/my-variant/cloud.cfg
    │                              │
    ▼                              ▼
┌──────────────────────────────────────────┐
│         generate-matrix.sh               │
│                                          │
│  noble × amd64 × base                   │
│  noble × amd64 × docker                 │
│  noble × amd64 × coding                 │
│  noble × amd64 × my-variant ◄── new!    │
│  ...                                     │
└──────────────────┬───────────────────────┘
                   │
                   ▼
          GitHub Actions Jobs
          (one job per combination)
                   │
                   ▼
         GitHub Release v2026.03.14.1
         ├─ ubuntu-noble-base-amd64.img
         ├─ ubuntu-noble-docker-amd64.img
         ├─ ubuntu-noble-coding-amd64.img
         ├─ ubuntu-noble-my-variant-amd64.img  ◄── new!
         ├─ manifest.json
         └─ checksums.sha256
```

## Environment Variables Reference

All variables are optional. Set them to skip the corresponding interactive prompt.

| Variable | Description | Default |
|----------|-------------|---------|
| `ARCH` | CPU architecture | `amd64` |
| `BASE` | Ubuntu codename | PVE 8.x → `noble`, 7.x → `jammy` |
| `VARIANT` | Image variant | `base` |
| `VM_ID` | Template VM ID | `9000` |
| `VM_NAME` | Template name | `<os>-<codename>-<variant>` |
| `STORAGE` | Disk storage | `local-lvm` |
| `CI_STORAGE` | Cloud-init storage | `local-lvm` |
| `MEMORY` | Memory (MB) | `2048` |
| `CORES` | CPU cores | `1` |
| `BRIDGE` | Network bridge | `vmbr0` |
| `ENABLE_DHCP` | Set DHCP on ipconfig0 | `yes` (when confirmed) |
| `GITHUB_TOKEN` | GitHub API token | *(unset)* — set to avoid rate limiting |

## Prerequisites

### PVE Host (install script)

- Root access
- `wget`, `jq`, `qm`

### Build (CI)

- `yq` v4+
- `libguestfs-tools` (provides `virt-edit`)
- `linux-image-generic`
- `make` (for release tagging)

## License

[MIT](LICENSE)
