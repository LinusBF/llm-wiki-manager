#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
    echo "This installer must run on Linux." >&2
    exit 1
fi

if [[ $# -ne 1 || "$1" != /* ]]; then
    echo "Usage: $0 /absolute/path/to/vault" >&2
    exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config/llm-wiki-manager"
UNIT_DIR="$HOME/.config/systemd/user"

cd "$ROOT_DIR"
swift build -c release --product llm-wiki-daemon
BUILD_DIR="$(swift build -c release --show-bin-path)"

install -d "$BIN_DIR" "$CONFIG_DIR" "$UNIT_DIR"
install -m 0755 "$BUILD_DIR/llm-wiki-daemon" "$BIN_DIR/llm-wiki-daemon"

for resources in "$BUILD_DIR"/*.resources "$BUILD_DIR"/*.bundle; do
    if [[ -d "$resources" ]]; then
        resource_name="$(basename "$resources")"
        rm -rf -- "${BIN_DIR:?}/${resource_name:?}"
        cp -R "$resources" "$BIN_DIR/"
    fi
done

install -m 0644 "$ROOT_DIR/Packaging/llm-wiki-manager.service" "$UNIT_DIR/llm-wiki-manager.service"

if [[ ! -e "$CONFIG_DIR/environment" ]]; then
    printf 'LLM_WIKI_VAULT=%s\nLLM_WIKI_AGENT=claude\nPATH=%s\n' "$1" "$PATH" > "$CONFIG_DIR/environment"
    chmod 0600 "$CONFIG_DIR/environment"
elif ! grep -q '^PATH=' "$CONFIG_DIR/environment"; then
    printf '\nPATH=%s\n' "$PATH" >> "$CONFIG_DIR/environment"
fi

systemctl --user daemon-reload
systemctl --user enable llm-wiki-manager.service
systemctl --user restart llm-wiki-manager.service

echo "Installed and started llm-wiki-manager.service"
echo "Logs: journalctl --user -u llm-wiki-manager.service -f"
