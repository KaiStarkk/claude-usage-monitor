#!/usr/bin/env bash
# Claude Usage Monitor - Installation Script
# https://github.com/KaiStarkk/claude-usage-monitor

set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/KaiStarkk/claude-usage-monitor/main"

echo "Claude Usage Monitor - Installer"
echo "================================="
echo ""

# Check dependencies
echo "Checking dependencies..."
for cmd in curl jq; do
  if ! command -v "$cmd" &> /dev/null; then
    echo "Error: $cmd is required but not installed."
    exit 1
  fi
done
echo "  curl: $(command -v curl)"
echo "  jq: $(command -v jq)"

# Check for Claude Code credentials
CREDS_FILE="$HOME/.claude/.credentials.json"
if [[ ! -f "$CREDS_FILE" ]]; then
  echo ""
  echo "Warning: Claude Code credentials not found at $CREDS_FILE"
  echo "Make sure you've authenticated Claude Code with 'claude' first."
fi

# Create install directory
echo ""
echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"

# Download scripts
echo "  Downloading claude-usage-statusline.sh..."
curl -sL "$REPO_URL/claude-usage-statusline.sh" -o "$INSTALL_DIR/claude-usage-statusline.sh"
chmod +x "$INSTALL_DIR/claude-usage-statusline.sh"

echo "  Downloading claude-usage-bar.sh..."
curl -sL "$REPO_URL/claude-usage-bar.sh" -o "$INSTALL_DIR/claude-usage-bar.sh"
chmod +x "$INSTALL_DIR/claude-usage-bar.sh"

echo "  Downloading claude-usage-cycle.sh..."
curl -sL "$REPO_URL/claude-usage-cycle.sh" -o "$INSTALL_DIR/claude-usage-cycle.sh"
chmod +x "$INSTALL_DIR/claude-usage-cycle.sh"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo ""
echo "1. For Claude Code statusline, add to ~/.claude/settings.json:"
echo '   {'
echo '     "statusLine": {'
echo '       "type": "command",'
echo '       "command": "~/.local/bin/claude-usage-statusline.sh",'
echo '       "padding": 0'
echo '     }'
echo '   }'
echo ""
echo "2. For waybar/hyprpanel, see examples at:"
echo "   https://github.com/KaiStarkk/claude-usage-monitor#integration"
echo ""
echo "3. Test the scripts:"
echo "   echo '{}' | ~/.local/bin/claude-usage-statusline.sh"
echo "   ~/.local/bin/claude-usage-bar.sh"
