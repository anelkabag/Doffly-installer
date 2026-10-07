#!/usr/bin/env bash
set -euo pipefail

RELEASE_REPO="anelkabag/Doffly-installer"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
INSTALL_SERVICE="${INSTALL_SERVICE:-true}"
DOFFLY_API_URL="${DOFFLY_API_URL:-https://api.doffly.pro}"
ENV_DIR="/etc/doffly"
ENV_FILE="${ENV_DIR}/agent.env"
MINISIGN_PUBLIC_KEY='untrusted comment: minisign public key 83010FCD2D3335CD
RWTNNTMtzQ8Bg1r07J1yOtnV88TPGyTtVSn0+cYfjN996RJQ4YPwl2uh'

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

UPDATE_MODE="false"
if [[ "${1:-}" == "--update" || "${DOFFLY_UPDATE:-false}" == "true" ]]; then
  UPDATE_MODE="true"
fi

if [[ "$UPDATE_MODE" == "false" ]]; then
  prompt_value() {
    local variable="$1"
    local label="$2"
    local secret="${3:-false}"
    local input

  [[ -n "${!variable:-}" ]] && return
  if [[ ! -r /dev/tty ]]; then
    echo "${variable} is required. Set it in the environment or run the installer from a terminal." >&2
    exit 1
  fi

  printf '%s' "$label" > /dev/tty
  if [[ "$secret" == "true" ]]; then
    IFS= read -r -s input < /dev/tty
    printf '\n' > /dev/tty
  else
    IFS= read -r input < /dev/tty
  fi
  printf -v "$variable" '%s' "$input"
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
  echo "Could not determine a valid release version. Set DOFFLY_VERSION (for example v0.3.3)." >&2
  exit 1
fi

CURRENT_VERSION="unknown"
if [[ -x "${INSTALL_DIR}/doffly-agent" ]]; then
  CURRENT_VERSION="$("${INSTALL_DIR}/doffly-agent" --version 2>/dev/null \
    | sed -nE 's/.*Using Doffly Agent version [vV]?([0-9]+\.[0-9]+\.[0-9]+).*/v\1/p' \
    | head -n 1 || true)"
  CURRENT_VERSION="${CURRENT_VERSION:-unknown}"
fi
ASSET="doffly-agent-linux-${ARCH}"
RELEASE_URL="https://github.com/${RELEASE_REPO}/releases/download/${VERSION}"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

if ! command -v minisign >/dev/null 2>&1; then
  echo "minisign is required to verify the Doffly Agent release." >&2
  exit 1
fi

printf '%s\n' "$MINISIGN_PUBLIC_KEY" > "$TMP_DIR/minisign.pub"
echo "Downloading Doffly Agent ${VERSION} (linux/${ARCH})..."
curl -fsSL --retry 3 "${RELEASE_URL}/${ASSET}" -o "$TMP_DIR/$ASSET"
curl -fsSL --retry 3 "${RELEASE_URL}/${ASSET}.minisig" -o "$TMP_DIR/$ASSET.minisig"

if ! minisign -V -p "$TMP_DIR/minisign.pub" -m "$TMP_DIR/$ASSET" -x "$TMP_DIR/$ASSET.minisig" -q; then
  echo "Signature verification failed; the agent was not installed." >&2
  exit 1
fi

install -d "$INSTALL_DIR"
install -m 0755 "$TMP_DIR/$ASSET" "${INSTALL_DIR}/doffly-agent"

if [[ "$INSTALL_SERVICE" == "true" ]]; then
  if [[ "$UPDATE_MODE" == "true" ]]; then
    systemctl daemon-reload
    systemctl restart doffly-agent
  else
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
fi

# ---------- Final output ----------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  GREEN=$'\033[1;32m'; CYAN=$'\033[1;36m'; DIM=$'\033[2m'
  BOLD=$'\033[1m'; RESET=$'\033[0m'
else
  GREEN=""; CYAN=""; DIM=""; BOLD=""; RESET=""
fi

if [[ "${LC_ALL:-${LANG:-}}" == *[Uu][Tt][Ff]-8* || "${LC_ALL:-${LANG:-}}" == *[Uu][Tt][Ff]8* ]]; then
  CHECK="✔"; ARROW="➜"; RULE="────────────────────────────────────────────"
else
  CHECK="[OK]"; ARROW="->"; RULE="--------------------------------------------"
fi

printf '\n%s' "$CYAN"
cat <<'LOGO'
 ____    ___   _____  _____  _     __   __
|  _ \  / _ \ |  ___||  ___|| |    \ \ / /
| | | || | | || |_   | |_   | |     \ V /
| |_| || |_| ||  _|  |  _|  | |___   | |
|____/  \___/ |_|    |_|    |_____|  |_|
LOGO
printf '%s' "$RESET"

if [[ "$UPDATE_MODE" == "true" ]]; then
  printf '\n%s%s Doffly Agent update completed successfully%s\n' "$GREEN" "$CHECK" "$RESET"
  printf '%s%s%s\n' "$DIM" "$RULE" "$RESET"
  printf '  %sPrevious version%s : %s\n' "$BOLD" "$RESET" "$CURRENT_VERSION"
  printf '  %sNew version     %s : %s\n' "$BOLD" "$RESET" "$VERSION"
  printf '  %sTransition      %s : %s → %s\n' "$BOLD" "$RESET" "$CURRENT_VERSION" "$VERSION"
  printf '  %sExecutable     %s : %s/doffly-agent\n' "$BOLD" "$RESET" "$INSTALL_DIR"
  if [[ "$INSTALL_SERVICE" == "true" ]]; then
    printf '  %sService         %s : restarted and enabled at startup\n' "$BOLD" "$RESET"
  else
    printf '  %sService         %s : binary-only mode, service not managed\n' "$BOLD" "$RESET"
  fi
else
  printf '\n%s%s Doffly Agent was installed successfully%s\n' "$GREEN" "$CHECK" "$RESET"
  printf '%s%s%s\n' "$DIM" "$RULE" "$RESET"
  printf '  %sVersion   %s : %s\n' "$BOLD" "$RESET" "$VERSION"
  printf '  %sAgent ID  %s : %s\n' "$BOLD" "$RESET" "$DOFFLY_AGENT_ID"
  printf '  %sExecutable%s : %s/doffly-agent\n' "$BOLD" "$RESET" "$INSTALL_DIR"
  if [[ "$INSTALL_SERVICE" == "true" ]]; then
    printf '  %sService   %s : running and enabled at startup\n' "$BOLD" "$RESET"
  else
    printf '  %sService   %s : not installed (binary-only mode)\n' "$BOLD" "$RESET"
  fi
fi
printf '%s%s%s\n' "$DIM" "$RULE" "$RESET"

printf '\n%s%s Next step%s\n' "$CYAN" "$ARROW" "$RESET"
if [[ "$UPDATE_MODE" == "true" ]]; then
  printf '  The agent has been updated from %s to %s.\n' "$CURRENT_VERSION" "$VERSION"
  printf '  Confirm that the agent appears online in your Doffly dashboard.\n'
  if [[ "$INSTALL_SERVICE" == "true" ]]; then
    printf '\n%s  Check the service :%s systemctl status doffly-agent\n' "$DIM" "$RESET"
    printf '%s  View the logs       :%s journalctl -u doffly-agent -f\n\n' "$DIM" "$RESET"
  fi
elif [[ "$INSTALL_SERVICE" == "true" ]]; then
  printf '  Open your Doffly dashboard and confirm that agent\n'
  printf '  %s%s%s appears online (the first connection may take a few moments).\n' "$BOLD" "$DOFFLY_AGENT_ID" "$RESET"
  printf '\n%s  Check the service :%s systemctl status doffly-agent\n' "$DIM" "$RESET"
  printf '%s  View the logs       :%s journalctl -u doffly-agent -f\n\n' "$DIM" "$RESET"
else
  printf '  Start the binary to connect this agent, then check your\n'
  printf '  Doffly dashboard to confirm that it appears online.\n\n'
fi