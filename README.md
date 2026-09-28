# Doffly Installer

Public installer and binary release assets for the Doffly Linux Agent. The Doffly source repository remains private; this repository contains only this README and `install.sh` in its default branch. Tagged binary releases are published here by the private source repository's GitHub Actions workflow.

## Install

Run on a supported Linux VPS. The installer prompts for the agent ID and one-time token generated in the Doffly dashboard. Token input is hidden. It installs the systemd service and defaults to `https://doffly.onrender.com`.

```bash
curl -fsSL https://raw.githubusercontent.com/anelkabag/Doffly-installer/main/install.sh | sudo bash
```

To pin a release:

```bash
curl -fsSL https://raw.githubusercontent.com/anelkabag/Doffly-installer/main/install.sh | sudo env DOFFLY_VERSION=v0.1.0 bash
```

Supported architectures are Linux `x86_64`/`amd64` and `aarch64`/`arm64`. The installer downloads the matching public GitHub Release asset, verifies it against `checksums.txt`, then installs `/usr/local/bin/doffly-agent` and configures `doffly-agent.service`.

When `get.doffly.dev` is configured, the short installer URL will be:

```bash
curl -fsSL https://get.doffly.dev/install.sh | sudo bash
```
