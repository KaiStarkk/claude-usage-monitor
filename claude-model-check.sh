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

# Normalize a model ID to short form: claude-TYPE-MAJOR-MINOR
# e.g. claude-opus-4-5-20251101 → claude-opus-4-5
#      claude-opus-4-6          → claude-opus-4-6
normalize_model() {
  local id=$1 type=$2
  local rest="${id#claude-${type}-}"
  IFS='-' read -ra parts <<< "$rest"
  local major="${parts[0]}"
  local minor=0
  if [[ ${#parts[@]} -ge 2 && ${#parts[1]} -le 2 ]]; then
    minor="${parts[1]}"
  fi
  echo "claude-${type}-${major}-${minor}"
}

# Extract the latest model for a given type from page content
# Handles both old format (claude-TYPE-X-Y-YYYYMMDD) and new (claude-TYPE-X-Y)
extract_latest() {
  local type=$1 page=$2
  echo "$page" \
    | grep -oE "claude-${type}-[0-9]+(-[0-9]+)*" \
    | grep -vE -- '-v[0-9]+$' \
    | sort -u \
    | while IFS= read -r id; do
        local rest="${id#claude-${type}-}"
        IFS='-' read -ra parts <<< "$rest"
        local major="${parts[0]}"
        local minor=0
        if [[ ${#parts[@]} -ge 2 && ${#parts[1]} -le 2 ]]; then
          minor="${parts[1]}"
        fi
        printf '%04d %04d claude-%s-%s-%s\n' "$major" "$minor" "$type" "$major" "$minor"
      done \
    | sort -k1,1nr -k2,2nr \
    | head -1 \
    | awk '{print $3}'
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
  tooltip="Current: $current_model\\nUnable to determine model type"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"unknown\"}"
  exit 0
fi

# Normalize current model to short form for comparison
current_short=$(normalize_model "$current_model" "$model_type")

# Check cache
cached_data=""
if [[ -f "$CACHE_FILE" ]]; then
  cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    cached_data=$(cat "$CACHE_FILE" 2>/dev/null)
  fi
fi

# Fetch latest models from Anthropic docs if cache is stale
if [[ -z "$cached_data" ]]; then
  docs_page=$(curl -sL --max-time 10 "$DOCS_URL" 2>/dev/null)

  if [[ -n "$docs_page" ]]; then
    latest_haiku=$(extract_latest "haiku" "$docs_page")
    latest_sonnet=$(extract_latest "sonnet" "$docs_page")
    latest_opus=$(extract_latest "opus" "$docs_page")

    cached_data="haiku:$latest_haiku"$'\n'"sonnet:$latest_sonnet"$'\n'"opus:$latest_opus"
    echo "$cached_data" > "$CACHE_FILE"
  fi
fi

# Extract the latest version for the current model type
latest_model=""
if [[ -n "$cached_data" ]]; then
  latest_model=$(echo "$cached_data" | grep "^${model_type}:" | cut -d: -f2)
fi

# Compare normalized short forms
if [[ -z "$latest_model" ]]; then
  tooltip="Current: $current_model\\nUnable to check for updates"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"unknown\"}"
elif [[ "$current_short" == "$latest_model" ]]; then
  tooltip="Current: $current_model\\nLatest: $latest_model\\n✓ Up to date"
  echo "{\"text\": \"\", \"tooltip\": \"$tooltip\", \"class\": \"up-to-date\"}"
else
  tooltip="Current: $current_model\\nLatest: $latest_model\\n⚠ Update available"
  echo "{\"text\": \"󰙨\", \"tooltip\": \"$tooltip\", \"class\": \"outdated\", \"latest\": \"$latest_model\"}"
fi
