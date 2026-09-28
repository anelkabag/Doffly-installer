# Doffly Installer

Public installer and binary release assets for the **Doffly Linux Agent**.

Doffly is a simple and lightweight server monitoring platform built for independent developers who want to monitor one or multiple Linux servers from a single dashboard.

The Doffly source repository remains private. This repository contains the public installer and release assets used to connect your servers to the Doffly platform.

## Install

Run the following command on a supported Linux VPS. The installer will prompt you for the **agent ID** and **one-time token** generated from your Doffly dashboard. Token input is hidden.

```bash
curl -fsSL https://raw.githubusercontent.com/anelkabag/Doffly-installer/main/install.sh | sudo bash
```

Once installed, the Doffly Agent runs as a systemd service and securely sends server metrics to Doffly, allowing you to monitor your server from a single dashboard.

By default, the agent connects to:

```text
https://doffly.onrender.com
```

## Pin a release

To install a specific Doffly Agent version:

```bash
curl -fsSL https://raw.githubusercontent.com/anelkabag/Doffly-installer/main/install.sh | sudo env DOFFLY_VERSION=v0.1.0 bash
```

## Supported systems

Doffly currently supports:

* Linux `x86_64` / `amd64`
* Linux `aarch64` / `arm64`

The installer automatically downloads the matching public GitHub Release asset and verifies it against `checksums.txt`.

The agent is installed at:

```text
/usr/local/bin/doffly-agent
```

and runs as:

```text
doffly-agent.service
```

## Monitoring

Once connected, your server can be monitored from the Doffly dashboard.

Doffly currently provides visibility into key server information such as:

* CPU usage
* Memory usage
* Disk usage
* Network activity
* Server status
* Machine information

This is only the beginning. **Doffly is actively evolving**, and new metrics, monitoring capabilities, and features will be added over time as the project grows.

The goal is simple: **connect your servers once and keep their monitoring information in one place.**

## Short installer URL

When `get.doffly.dev` is configured, the recommended installation command will be:

```bash
curl -fsSL https://get.doffly.dev/install.sh | sudo bash
```

## About Doffly

Doffly is built for developers who manage their own infrastructure and want server monitoring without the complexity of a large monitoring stack.

**Simple. Lightweight. Centralized. Built with Rust.**
