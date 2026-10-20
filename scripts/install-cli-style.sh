#!/usr/bin/env bash
# Installs cli-style into this repository's agent tools directory.

set -euo pipefail

# The cli-style release installed for this repository.
VERSION="0.10.0"
# The folder containing this installer, regardless of the caller's location.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
# The repository that receives the local cli-style installation.
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
# The folder where the cli-style binary and version marker are stored.
INSTALL_DIR="$REPO_DIR/.agent/tools/cli-style"

# The operating system name used in the release archive name.
platform=$(uname -s | tr '[:upper:]' '[:lower:]')
# The machine architecture used to select a compatible release archive.
architecture=$(uname -m)

case "$architecture" in
	arm64|aarch64) architecture="arm64" ;;
	x86_64|amd64) architecture="x64" ;;
esac

# The name of the release archive matching this machine's operating system and architecture.
archive="cli-style-$platform-$architecture.tar.gz"
# The download address for the selected cli-style release archive.
url="https://github.com/lewishowles/cli-style/releases/download/v$VERSION/$archive"
# The temporary download file removed when the installer exits.
temp_archive=$(mktemp)

trap 'rm -f "$temp_archive"' EXIT

mkdir -p "$INSTALL_DIR"
curl --connect-timeout 10 --max-time 600 --retry 2 -fsSL "$url" -o "$temp_archive"
tar -xzf "$temp_archive" -C "$INSTALL_DIR"
printf '%s\n' "$VERSION" > "$INSTALL_DIR/VERSION"

source "$REPO_DIR/scripts/lib/cli-style-output.sh"
cli_section "Installer" "Install local cli-style binary"
cli_status success "cli-style installed"
