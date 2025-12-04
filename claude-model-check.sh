#!/usr/bin/env bash
# Claude Model Check - Checks if your Claude Code model is up to date
# https://github.com/KaiStarkk/claude-usage-monitor
#
# Requirements: curl, jq
#
# Output format (JSON for bars):
#   {"text": "...", "tooltip": "...", "class": "up-to-date|outdated|error", "latest": "..."}
#
# Configuration (environment variables):
#   CLAUDE_MODEL_CACHE_TTL   - Cache TTL in seconds (default: 3600)
#   CLAUDE_SETTINGS_FILE     - Path to settings (default: ~/.claude/settings.json)

set -euo pipefail

# Configuration
CACHE_TTL="${CLAUDE_MODEL_CACHE_TTL:-3600}"
CACHE_FILE="/tmp/claude-model-check-cache"
SETTINGS_FILE="${CLAUDE_SETTINGS_FILE:-$HOME/.claude/settings.json}"
DOCS_URL="https://docs.anthropic.com/en/docs/about-claude/models/all-models"

# Output error JSON
error_json() {
  echo "{\"text\": \"?\", \"tooltip\": \"$1\", \"class\": \"error\"}"
  exit 0
}

# Read current model from settings
if [[ ! -f "$SETTINGS_FILE" ]]; then
  error_json "Claude settings not found"
fi

current_model=$(jq -r '.model // "unknown"' "$SETTINGS_FILE" 2>/dev/null)
if [[ -z "$current_model" || "$current_model" == "null" ]]; then
  current_model="unknown"
fi

# Extract model type (haiku, sonnet, opus) from current model
model_type=""
if [[ "$current_model" =~ claude-(haiku|sonnet|opus)- ]]; then
  model_type="${BASH_REMATCH[1]}"
else
  # Can't determine type, show unknown
  tooltip="Current: $current_model\\nUnable to determine model type"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"unknown\"}"
  exit 0
fi

# Check cache for latest model info (stores all three types)
cached_data=""
if [[ -f "$CACHE_FILE" ]]; then
  cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cached_data=$(cat "$CACHE_FILE" 2>/dev/null)
  fi
fi

# Fetch latest models from Anthropic docs if cache is stale or missing
if [[ -z "$cached_data" ]]; then
  docs_page=$(curl -sL --max-time 10 "$DOCS_URL" 2>/dev/null)

  if [[ -n "$docs_page" ]]; then
    # Extract latest haiku, sonnet, and opus models (format: claude-TYPE-X-Y-YYYYMMDD)
    latest_haiku=$(echo "$docs_page" | grep -oE 'claude-haiku-[0-9]+-[0-9]+-[0-9]+' | sort -u | sort -t'-' -k3,3nr -k4,4nr -k5,5nr | head -1)
    latest_sonnet=$(echo "$docs_page" | grep -oE 'claude-sonnet-[0-9]+-[0-9]+-[0-9]+' | sort -u | sort -t'-' -k3,3nr -k4,4nr -k5,5nr | head -1)
    latest_opus=$(echo "$docs_page" | grep -oE 'claude-opus-[0-9]+-[0-9]+-[0-9]+' | sort -u | sort -t'-' -k3,3nr -k4,4nr -k5,5nr | head -1)

    # Store all three in cache (one per line)
    cached_data="haiku:$latest_haiku"$'\n'"sonnet:$latest_sonnet"$'\n'"opus:$latest_opus"
    echo "$cached_data" > "$CACHE_FILE"
  fi
fi

# Extract the latest version for the current model type
latest_model=""
if [[ -n "$cached_data" ]]; then
  latest_model=$(echo "$cached_data" | grep "^${model_type}:" | cut -d: -f2)
fi

# Compare versions and output result
if [[ -z "$latest_model" ]]; then
  # No data available, just show current model
  tooltip="Current: $current_model\\nUnable to check for updates"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"unknown\"}"
elif [[ "$current_model" == "$latest_model" ]]; then
  tooltip="Current: $current_model\\nLatest: $latest_model\\n✓ Up to date"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"up-to-date\"}"
else
  tooltip="Current: $current_model\\nLatest: $latest_model\\n⚠ Update available"
  echo "{\"text\": \"󰙨\", \"tooltip\": \"$tooltip\", \"class\": \"outdated\", \"latest\": \"$latest_model\"}"
fi
