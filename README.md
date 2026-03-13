# PVE Base Image

Automate building customized Proxmox VE Cloud Images and provide a one-liner to import them as PVE Templates.

```
                    ┌─────────────────────────────────────────────┐
                    │              GitHub Actions CI              │
                    │                                             │
  images.yml ──────►│  base/cloud.cfg ─┐                          │
                    │                  ├─ yq merge ─► virt-edit ──┼──► GitHub Release
  variants/         │  variants/       │                          │      ├─ *.img
  └─ docker/  ─────►│  └─ cloud.cfg ───┘                          │      ├─ manifest.json
  └─ nodejs/        │                                             │      └─ checksums.sha256
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
curl -fsSL <install.sh URL> | bash
```

The script will guide you through:

1. **Architecture** — amd64 or arm64
2. **Distribution** — Ubuntu codename (e.g., noble, jammy)
3. **Variant** — base, docker, nodejs, etc.
4. **Template settings** — VM ID, storage, memory, CPU, network (all have sensible defaults)

```
┌─── Phase 1: Image Selection ───────────────────────────┐
│                                                        │
│  Architecture?   [1] amd64  [2] arm64                  │
│  Distribution?   [1] noble (24.04)  [2] jammy (22.04)  │
│  Variant?        [1] base  [2] docker  [3] nodejs      │
│                                                        │
├─── Phase 2: Template Defaults (Enter = accept) ────────┤
│                                                        │
│  VM ID?          9000                                  │
│  VM Name?        cloud-noble-docker                    │
│  Storage?        local-lvm                             │
│  Memory?         2048 MB                               │
│  CPU Cores?      1                                     │
│  Network?        vmbr0                                 │
│                                                        │
└────────────────────────────────────────────────────────┘
```

After completion, clone the Template to create VMs:

```bash
qm clone 9000 100 --name my-vm
qm set 100 --ciuser admin --cipassword secret --ipconfig0 ip=dhcp
qm start 100
```

### Non-interactive Mode

Use environment variables to skip prompts, useful for Ansible or batch deployments:

```bash
curl -fsSL <install.sh URL> | VM_ID=9000 VARIANT=docker bash
```

## Add a New Variant

1. Create a cloud-init config:

```bash
mkdir -p variants/nodejs
cat > variants/nodejs/cloud.cfg <<'EOF'
packages:
  - nodejs
  - npm
EOF
```

2. Add the variant to `images.yml`:

```yaml
variants:
  - name: base
    display_name: ""
  - name: nodejs
    display_name: "Node.js"
```

3. Push to main and tag a release:

```bash
git push origin main
git tag v2026.03.13 && git push origin v2026.03.13
```

CI automatically builds images for all `codename × arch × variant` combinations and uploads them to the GitHub Release.

```
images.yml                variants/nodejs/cloud.cfg
    │                              │
    ▼                              ▼
┌──────────────────────────────────────────┐
│         generate-matrix.sh               │
│                                          │
│  noble × amd64 × base                   │
│  noble × amd64 × nodejs   ◄── new!      │
│  noble × arm64 × base                   │
│  noble × arm64 × nodejs   ◄── new!      │
│  ...                                     │
└──────────────────┬───────────────────────┘
                   │
                   ▼
          GitHub Actions Jobs
          (one job per combination)
                   │
                   ▼
         GitHub Release v2026.03.13
         ├─ ubuntu-noble-base-amd64.img
         ├─ ubuntu-noble-nodejs-amd64.img  ◄── new!
         ├─ ubuntu-noble-base-arm64.img
         ├─ ubuntu-noble-nodejs-arm64.img  ◄── new!
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
| `VM_NAME` | Template name | `cloud-<codename>-<variant>` |
| `STORAGE` | Disk storage | `local-lvm` |
| `CI_STORAGE` | Cloud-init storage | `local-lvm` |
| `MEMORY` | Memory (MB) | `2048` |
| `CORES` | CPU cores | `1` |
| `BRIDGE` | Network bridge | `vmbr0` |
| `GITHUB_TOKEN` | GitHub API token | *(unset)* — set to avoid rate limiting |

## Prerequisites

### PVE Host (install script)

- Root access
- `wget`, `jq`, `qm`

### Build (CI)

- `yq` v4+
- `libguestfs-tools` (provides `virt-edit`)
- `linux-image-generic`

## License

[MIT](LICENSE)
