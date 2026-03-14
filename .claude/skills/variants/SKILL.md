---
name: variants
description: Create new PVE image variants with cloud-init configuration. Use this skill whenever the user wants to add a new variant, create a variant cloud.cfg, add packages to an image, set up a new software stack for PVE templates, or modify images.yml to include new variants. Also use when the user mentions adding tools like Kubernetes, monitoring agents, databases, or any software stack to their PVE base images — even if they don't explicitly say "variant".
---

# Variants Skill

Build new PVE image variants by creating cloud-init configurations and registering them in `images.yml`. This skill ensures all generated configs comply with cloud-init constraints and PVE template requirements.

## Workflow

### Step 1: Understand the user's intent

Ask the user what they want in their variant:

1. **Variant name** — lowercase, no spaces (used as directory name under `variants/`)
2. **Display name** — human-readable label shown in the install menu (e.g., "Kubernetes Node")
3. **Required packages** — what software to install (APT packages, external repos, binary downloads)
4. **Snippets to reuse** — check existing snippets in `snippets/` and ask if any apply

### Step 2: Research package installation

For each requested package, determine the correct installation method:

- **APT packages**: list under `packages:` in cloud.cfg
- **External APT repos** (Docker, Kubernetes, etc.): add repo setup commands to `runcmd:`, then install via `apt-get install -y`
- **Binary downloads** (mise, standalone tools): use `curl` in `runcmd:`
- **pip/npm/gem packages**: install the runtime first, then use the package manager in `runcmd:`

When adding external APT repositories, follow this pattern:

```yaml
runcmd:
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://example.com/gpg -o /etc/apt/keyrings/example.asc
  - chmod a+r /etc/apt/keyrings/example.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/example.asc] https://example.com/repo $(. /etc/os-release && echo ${VERSION_CODENAME}) stable" > /etc/apt/sources-example.list
  - cp /etc/apt/sources-example.list /etc/apt/sources.list.d/example.list
  - apt-get update
  - apt-get install -y package-name
```

**Verify URLs**: Before writing config, use WebSearch or WebFetch to confirm the actual GPG key URL and repository URL for the target software. Package repositories change over time — never assume a URL is correct without checking.

### Step 3: Check for reusable snippets

Read `images.yml` and list existing snippets. If the user's variant needs Docker, point out the existing `docker` snippet instead of recreating it. If a common component could be reused by future variants, suggest extracting it as a new snippet in `snippets/`.

### Step 4: Create the variant configuration

Create `variants/{name}/cloud.cfg` following these rules. Read `references/cloud-init-constraints.md` for the full list of constraints before writing any config.

**Config structure:**

```yaml
packages:
  - package1
  - package2

runcmd:
  - command1
  - command2
```

Only include `packages:` and `runcmd:` sections that the variant adds. The base config (`base/cloud.cfg`) already handles:
- `manage_etc_hosts: true`
- `qemu-guest-agent` package and service
- `package_update: true` / `package_upgrade: true`
- `ssh_pwauth: false`

Do NOT duplicate these in variant configs.

### Step 5: Register in images.yml

Add the variant entry to `images.yml` under `variants:`:

```yaml
variants:
  # ... existing variants ...
  - name: my-variant
    display_name: "My Variant Display Name"
    snippets:
      - docker  # only if needed
```

If the variant uses no snippets, either omit `snippets:` or use an empty list.

### Step 6: Validate

After creating the files, run the build tests to verify:

```bash
bats test/build.bats
```

All tests must pass. If a test fails, fix the config and re-run.

### Step 7: Suggest variant-specific tests (optional)

If the variant has complex runcmd logic (like the coding variant's mise setup), suggest adding variant-specific test cases to `test/build.bats`. Follow the existing pattern:

```bash
@test "build: {variant} variant {what it checks}" {
  local variant_cfg="${REPO_ROOT}/variants/{name}/cloud.cfg"
  # assertions here
}
```

## Handling non-Ubuntu base requests

### Debian

Debian cloud images support cloud-init and use APT, so the variant system is largely compatible. If a user wants Debian:

1. Guide them to add a new entry in `images.yml` under `bases:` with:
   - The Debian cloud image URL (e.g., `https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-{arch}.qcow2`)
   - Verify the URL exists for each architecture via WebFetch
2. Existing snippets (like `docker`) use `$(. /etc/os-release && echo ${VERSION_CODENAME})` which works on Debian too
3. Some packages may have different names between Ubuntu and Debian — verify with the user
4. Debian minimal images may not exist for all architectures — check availability

### Incompatible distributions (Arch Linux, Alpine, etc.)

Clearly explain why these distributions are NOT supported:

- **Package manager mismatch**: The entire config pipeline assumes APT (`packages:` maps to apt, `runcmd:` uses `apt-get`). Arch uses pacman, Alpine uses apk — all existing snippets and base config would break.
- **No cloud-init support**: Some distros lack official cloud images with cloud-init pre-installed.
- **Snippet incompatibility**: All existing snippets assume Debian/Ubuntu APT repository setup patterns (keyrings, sources.list.d).

Suggest the user either:
- Use Debian as an alternative if they want something non-Ubuntu
- Build a separate toolchain if they truly need a non-APT distribution

Do NOT attempt to create variant configs for incompatible distributions — it will produce non-functional images.

## Creating new snippets

If a component should be reusable across variants, create it as `snippets/{name}.cfg` instead of putting it in the variant config. Then reference it in `images.yml` under the variant's `snippets:` list.

A snippet is appropriate when:
- Multiple variants would use the same setup (e.g., Docker, monitoring agents)
- The setup is self-contained and doesn't depend on variant-specific configuration
