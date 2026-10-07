#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/fake-bin"
INSTALL_DIR="$TMP_DIR/install"
mkdir -p "$FAKE_BIN" "$INSTALL_DIR"

cat > "$FAKE_BIN/curl" <<'CURL'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *"releases/latest"* ]]; then
  printf '%s\n' '{"tag_name":"v0.3.2"}'
  exit 0
fi
output=""
next_argument=false
for argument in "$@"; do
  if [[ "$argument" == "-o" ]]; then
    next_argument=true
  elif [[ "$next_argument" == true ]]; then
    output="$argument"
    next_argument=false
  fi
done
printf 'new-agent-binary' > "$output"
CURL
cat > "$FAKE_BIN/minisign" <<'MINISIGN'
#!/usr/bin/env bash
exit 0
MINISIGN
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/minisign"
cat > "$INSTALL_DIR/doffly-agent" <<'AGENT'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'Using Doffly version 0.3.0\n'
  exit 0
fi
printf 'Doffly agent v0.3.0\n9.4.0 dependency-version\nold-agent-binary\n'
AGENT
chmod +x "$INSTALL_DIR/doffly-agent"

set +e
output="$(PATH="$FAKE_BIN:$PATH" \
  INSTALL_DIR="$INSTALL_DIR" \
  INSTALL_SERVICE=false \
  DOFFLY_AGENT_ID=existing-agent \
  DOFFLY_AGENT_TOKEN=existing-token \
  DOFFLY_API_URL=https://api.doffly.pro \
  bash "$ROOT_DIR/install.sh" --update 2>&1)"
status=$?
set -e

if [[ $status -ne 0 ]]; then
  printf '%s\n' "$output" >&2
  exit "$status"
fi

if ! grep -Fq 'v0.3.0 → v0.3.2' <<<"$output"; then
  printf '%s\n' "$output" >&2
  echo 'Expected an automatic v0.3.0 to v0.3.2 update message.' >&2
  exit 1
fi

if ! grep -Fq 'Doffly Agent update completed successfully' <<<"$output"; then
  printf '%s\n' "$output" >&2
  echo 'Expected a clear update completion message.' >&2
  exit 1
fi
