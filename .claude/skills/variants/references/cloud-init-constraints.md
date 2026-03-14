# Cloud-Init Constraints for PVE Variants

These constraints MUST be followed when writing cloud-init configs for this project. Violating any of them will cause runtime failures that are difficult to debug.

## Shell execution

**runcmd runs under /bin/sh (dash), not bash.** This means:

- No bash arrays, `[[ ]]` tests, `{a,b}` brace expansion, or process substitution `<()`
- No `eval "$(tool activate bash)"` — dash cannot parse bash-specific output
- Use `$(command)` for command substitution (POSIX-compatible)
- For tools that need bash activation (like mise), write a heredoc to `/etc/profile.d/` instead:

```yaml
runcmd:
  - |
    cat > /etc/profile.d/tool.sh <<'PROFILE'
    eval "$(/usr/local/bin/tool activate bash)"
    PROFILE
```

## Drop-in files only

**Never overwrite `/etc/cloud/cloud.cfg`.** All custom config goes to `/etc/cloud/cloud.cfg.d/99_pve.cfg`. Overwriting the main cloud.cfg destroys module lists and system_info, breaking SSH key injection, user creation, and more.

This is handled automatically by the build pipeline — variant configs are merged and injected as the drop-in file.

## Array merging

The merge pipeline uses `yq eval-all 'select(fileIndex==0) *+ select(fileIndex==1)'`. The `*+` operator concatenates arrays. This means:

- Variant `packages:` entries are ADDED to base packages (not replacing)
- Variant `runcmd:` entries are APPENDED to base runcmd (not replacing)
- You only need to list NEW packages and commands in your variant config

## Command ordering in runcmd

Commands execute in the order listed. Be careful about dependencies:

1. Repository setup (keyrings, sources.list) must come before `apt-get install`
2. Tool installation must come before tool usage
3. `chmod -R a+rX` must come AFTER all file installations (npm install, etc.)
4. `systemctl enable --now` should be the last step for each service

## mise-specific rules

If using mise in a variant:

- System config path: `/etc/mise/config.toml` (NOT `/etc/mise.toml`)
- Data directory: `/usr/local/share/mise` (system-wide, not user-specific)
- `mise exec` must specify tool@version (e.g., `node@lts`, `python@3.12`)
- `chmod -R a+rX /usr/local/share/mise` must be the FINAL runcmd step
- Activation goes in profile.d scripts, not in runcmd directly

## External APT repositories

When adding third-party APT repos:

1. Create keyring directory: `install -m 0755 -d /etc/apt/keyrings`
2. Download GPG key to `/etc/apt/keyrings/{name}.asc`
3. Write sources list to `/etc/apt/sources-{name}.list` first
4. Copy to `/etc/apt/sources.list.d/{name}.list`
5. Run `apt-get update` before installing packages

Use `$(dpkg --print-architecture)` for arch and `$(. /etc/os-release && echo ${VERSION_CODENAME})` for Ubuntu codename — these are POSIX-compatible.

## PVE template requirements

- `qemu-guest-agent` is already in the base config — do not add it again
- VM config must include `--agent enabled=1` (handled by install.sh, not cloud-init)
- `package_update` and `package_upgrade` are already in base — do not duplicate

## Testing

After creating a variant, run `bats test/build.bats` to verify:

- Merged YAML is valid
- packages and runcmd sections exist in merged config
- Referenced snippets exist as files
- Variant-specific constraints are met (if tests exist)
