#!/data/data/com.termux/files/usr/bin/bash
# ═══════════════════════════════════════════════════════════════════
# termux-agents-hub — One-line Installer
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/Ryuupyroxi/termux-agents-hub/main/install.sh)"
# ═══════════════════════════════════════════════════════════════════
set -euo pipefail

REPO="Ryuupyroxi/termux-agents-hub"
SCRIPT="termux-agents-hub.sh"
URL="https://raw.githubusercontent.com/${REPO}/main/${SCRIPT}"
DEST="${HOME}/${SCRIPT}"

echo "╔══════════════════════════════════════════════════╗"
echo "║  termux-agents-hub — Installer                  ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Check we're in Termux
if [[ ! -d "/data/data/com.termux" ]] && [[ -z "${TERMUX_VERSION:-}" ]]; then
  echo "⚠  This installer is designed for Termux on Android."
  echo "   Detected: $(uname -s) $(uname -m)"
  echo ""
fi

# Update packages
echo "▸ Updating packages..."
pkg update -y 2>/dev/null || apt update -y 2>/dev/null || true

# Install dependencies
echo "▸ Installing dependencies..."
for pkg in nodejs python git curl termux-api; do
  if ! command -v "${pkg}" >/dev/null 2>&1; then
    echo "  Installing ${pkg}..."
    pkg install -y "${pkg}" 2>/dev/null || apt install -y "${pkg}" 2>/dev/null || true
  else
    echo "  ${pkg}: ✓ already installed"
  fi
done

# Download the hub script
echo ""
echo "▸ Downloading ${SCRIPT}..."
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${URL}" -o "${DEST}" || { echo "❌ Download failed. Try manually:"; echo "   curl -O ${URL}"; exit 1; }
elif command -v wget >/dev/null 2>&1; then
  wget -q "${URL}" -O "${DEST}" || { echo "❌ Download failed. Try manually:"; echo "   wget ${URL}"; exit 1; }
else
  echo "❌ Neither curl nor wget found. Install one:"
  echo "   pkg install curl"
  exit 1
fi

chmod +x "${DEST}"

# Verify and execute
if [[ -f "${DEST}" ]] && head -1 "${DEST}" | grep -q "bash"; then
  echo ""
  echo "✅ Downloaded and ready: ${DEST}"
  echo ""
  echo "▸ Launching termux-agents-hub..."
  echo ""
  
  # Redirect standard input back to the user's terminal (TTY) 
  # This makes it fully interactive, even if the installer itself was piped!
  if [ ! -t 0 ]; then
    exec bash "${DEST}" "$@" </dev/tty
  else
    exec bash "${DEST}" "$@"
  fi
else
  echo "❌ Download appears corrupted"
  echo "   Expected bash script, got:"
  head -1 "${DEST}" 2>/dev/null || echo "   (empty file)"
  exit 1
fi
