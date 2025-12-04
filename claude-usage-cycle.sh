#!/usr/bin/env bash
# Claude Usage Cycle - Cycle through display options
# https://github.com/KaiStarkk/claude-usage-monitor
#
# Usage:
#   claude-usage-cycle style [up|down]   - Cycle bar styles
#   claude-usage-cycle display [up|down] - Cycle display modes
#   claude-usage-cycle format [up|down]  - Cycle formats
#   claude-usage-cycle reset             - Reset to defaults

set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-usage"
CONFIG_FILE="$CONFIG_DIR/config"
CACHE_FILE="/tmp/claude-usage-bar-cache"

# Available options
STYLES=(unicode ascii braille minimal)
DISPLAYS=(all 5h 7d sonnet)

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Read current config
read_config() {
  local key=$1
  local default=$2
  if [[ -f "$CONFIG_FILE" ]]; then
    local value=$(grep "^${key}=" "$CONFIG_FILE" 2>/dev/null | cut -d= -f2)
    echo "${value:-$default}"
  else
    echo "$default"
  fi
}

# Write config value
write_config() {
  local key=$1
  local value=$2

  if [[ -f "$CONFIG_FILE" ]]; then
    # Remove existing key
    grep -v "^${key}=" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null || true
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  fi

  # Add new value
  echo "${key}=${value}" >> "$CONFIG_FILE"

  # Invalidate cache
  rm -f "$CACHE_FILE"
}

# Get next/prev item in array
cycle_array() {
  local current=$1
  local direction=$2
  shift 2
  local arr=("$@")
  local len=${#arr[@]}

  # Find current index
  local idx=0
  for i in "${!arr[@]}"; do
    if [[ "${arr[$i]}" == "$current" ]]; then
      idx=$i
      break
    fi
  done

  # Calculate new index
  if [[ "$direction" == "up" || "$direction" == "next" ]]; then
    idx=$(( (idx + 1) % len ))
  else
    idx=$(( (idx - 1 + len) % len ))
  fi

  echo "${arr[$idx]}"
}

# Main logic
action="${1:-}"
direction="${2:-up}"

case "$action" in
  style)
    current=$(read_config "style" "unicode")
    new=$(cycle_array "$current" "$direction" "${STYLES[@]}")
    write_config "style" "$new"
    echo "Style: $new"
    ;;
  display)
    current=$(read_config "display" "all")
    new=$(cycle_array "$current" "$direction" "${DISPLAYS[@]}")
    write_config "display" "$new"
    echo "Display: $new"
    ;;
  reset)
    rm -f "$CONFIG_FILE" "$CACHE_FILE"
    echo "Reset to defaults"
    ;;
  status)
    echo "style=$(read_config style unicode)"
    echo "display=$(read_config display all)"
    ;;
  *)
    echo "Usage: claude-usage-cycle <style|display|reset|status> [up|down]"
    echo ""
    echo "Options:"
    echo "  style   - Cycle: unicode → ascii → braille → minimal"
    echo "  display - Cycle: all → 5h → 7d → sonnet"
    echo "  reset   - Reset all to defaults"
    echo "  status  - Show current settings"
    exit 1
    ;;
esac
