#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="anelkabag/Doffly-installer"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
INSTALL_SERVICE="${INSTALL_SERVICE:-true}"
DOFFLY_API_URL="${DOFFLY_API_URL:-https://doffly.onrender.com}"
ENV_DIR="/etc/doffly"
ENV_FILE="${ENV_DIR}/agent.env"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "Doffly Agent currently supports Linux only." >&2
  exit 1
fi

case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *)
    echo "Unsupported architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

if [[ "$(id -u)" -ne 0 && ( "$INSTALL_SERVICE" == "true" || "$INSTALL_DIR" == "/usr/local/bin" ) ]]; then
  echo "Run the installer as root (for example, through sudo)." >&2
  exit 1
fi

if [[ "$INSTALL_SERVICE" == "true" ]] && ! command -v systemctl >/dev/null 2>&1; then
  echo "systemd is required to install the service; set INSTALL_SERVICE=false to install only the binary." >&2
  exit 1
fi

prompt_value() {
  local variable="$1"
  local label="$2"
  local secret="${3:-false}"

  [[ -n "${!variable:-}" ]] && return
  if [[ ! -r /dev/tty ]]; then
    echo "${variable} is required. Set it in the environment or run the installer from a terminal." >&2
    exit 1
  fi

  printf '%s' "$label" > /dev/tty
  if [[ "$secret" == "true" ]]; then
    IFS= read -r -s "$variable" < /dev/tty
    printf '\n' > /dev/tty
  else
    IFS= read -r "$variable" < /dev/tty
  fi
}

prompt_value DOFFLY_AGENT_ID "Doffly Agent ID: "
prompt_value DOFFLY_AGENT_TOKEN "Doffly Agent token: " true

if [[ ! "$DOFFLY_AGENT_ID" =~ ^[A-Za-z0-9_-]{1,128}$ ]]; then
  echo "Invalid DOFFLY_AGENT_ID." >&2
  exit 1
fi
if [[ ! "$DOFFLY_AGENT_TOKEN" =~ ^[A-Za-z0-9_-]{20,}$ ]]; then
  echo "Invalid DOFFLY_AGENT_TOKEN." >&2
  exit 1
fi
if [[ ! "$DOFFLY_API_URL" =~ ^https?://[A-Za-z0-9._:/-]+$ ]]; then
  echo "Invalid DOFFLY_API_URL." >&2
  exit 1
fi

VERSION="${DOFFLY_VERSION:-${VERSION:-}}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(curl -fsSL --retry 3 "https://api.github.com/repos/${RELEASE_REPO}/releases/latest" \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
fi

if [[ ! "$VERSION" =~ ^v[0-9][A-Za-z0-9._+-]*$ ]]; then
  echo "Could not determine a valid release version. Set DOFFLY_VERSION (for example v0.1.0)." >&2
  exit 1
fi

ASSET="doffly-agent-linux-${ARCH}"
RELEASE_URL="https://github.com/${RELEASE_REPO}/releases/download/${VERSION}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading Doffly Agent ${VERSION} (linux/${ARCH})..."
curl -fsSL --retry 3 "${RELEASE_URL}/${ASSET}" -o "$TMP_DIR/$ASSET"
curl -fsSL --retry 3 "${RELEASE_URL}/checksums.txt" -o "$TMP_DIR/checksums.txt"

CHECKSUM="$(awk -v asset="$ASSET" '$2 == asset { print $1; exit }' "$TMP_DIR/checksums.txt")"
if [[ ! "$CHECKSUM" =~ ^[A-Fa-f0-9]{64}$ ]]; then
  echo "No valid SHA-256 checksum found for ${ASSET}." >&2
  exit 1
fi
printf '%s  %s\n' "$CHECKSUM" "$TMP_DIR/$ASSET" | sha256sum --check --status - || {
  echo "SHA-256 verification failed; the agent was not installed." >&2
  exit 1
}

install -d "$INSTALL_DIR"
install -m 0755 "$TMP_DIR/$ASSET" "${INSTALL_DIR}/doffly-agent"

if [[ "$INSTALL_SERVICE" == "true" ]]; then
  if ! getent group doffly >/dev/null; then
    groupadd --system doffly
  fi
  if ! id doffly >/dev/null 2>&1; then
    useradd --system --gid doffly --home-dir /var/lib/doffly \
      --create-home --shell /usr/sbin/nologin doffly
  fi

  if [[ -f /etc/systemd/system/doffly.service ]]; then
    systemctl disable --now doffly
    rm -f /etc/systemd/system/doffly.service
    systemctl daemon-reload
  fi

  install -d -o root -g root -m 0700 "$ENV_DIR"
  env_tmp="$(mktemp "${ENV_DIR}/agent.env.XXXXXX")"
  printf 'DOFFLY_API_URL=%s\nDOFFLY_AGENT_ID=%s\nDOFFLY_AGENT_TOKEN=%s\nDOFFLY_AGENT_ADDR=127.0.0.1:9090\n' \
    "$DOFFLY_API_URL" "$DOFFLY_AGENT_ID" "$DOFFLY_AGENT_TOKEN" > "$env_tmp"
  chown root:root "$env_tmp"
  chmod 0600 "$env_tmp"
  mv "$env_tmp" "$ENV_FILE"

  cat > /etc/systemd/system/doffly-agent.service <<EOF
[Unit]
Description=Doffly monitoring agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=doffly
Group=doffly
WorkingDirectory=/var/lib/doffly
EnvironmentFile=${ENV_FILE}
ExecStart=${INSTALL_DIR}/doffly-agent
Restart=on-failure
RestartSec=5s
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/doffly
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=true
MemoryDenyWriteExecute=true
RestrictRealtime=true
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now doffly-agent
fi

echo "Doffly Agent ${VERSION} installed at ${INSTALL_DIR}/doffly-agent."

if [[ "$INSTALL_SERVICE" == "true" ]]; then
  echo "Service status: systemctl status doffly-agent"
  echo "The agent is connected as ${DOFFLY_AGENT_ID}; it uses outbound HTTPS only."
fi
