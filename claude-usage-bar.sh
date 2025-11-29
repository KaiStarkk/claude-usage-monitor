#!/usr/bin/env bash
# Claude Usage Bar - Outputs JSON for status bars (waybar, hyprpanel, etc.)
# https://github.com/KaiStarkk/claude-usage-monitor
#
# Requirements: curl, jq, Claude Code with OAuth authentication
#
# Output format (JSON):
#   {"text": "...", "tooltip": "...", "class": "normal|warning|critical"}
#
# Configuration (environment variables):
#   CLAUDE_USAGE_BAR_WIDTH  - Width of progress bars (default: 8)
#   CLAUDE_USAGE_BAR_STYLE  - Bar style: ascii, unicode, braille (default: unicode)
#   CLAUDE_USAGE_DISPLAY    - Display mode: all, 5h, 7d, minimal (default: all)
#   CLAUDE_USAGE_FORMAT     - Format: bars, percent, time (default: bars)
#   CLAUDE_USAGE_CACHE_TTL  - Cache TTL in seconds (default: 300)
#   CLAUDE_CREDENTIALS_FILE - Path to credentials (default: ~/.claude/.credentials.json)
#
# Config file: ~/.config/claude-usage/config (overrides env vars)
#   style=unicode
#   display=all
#   format=bars

set -euo pipefail

# Configuration defaults
BAR_WIDTH="${CLAUDE_USAGE_BAR_WIDTH:-8}"
BAR_STYLE="${CLAUDE_USAGE_BAR_STYLE:-unicode}"
DISPLAY_MODE="${CLAUDE_USAGE_DISPLAY:-all}"
FORMAT="${CLAUDE_USAGE_FORMAT:-bars}"
CACHE_TTL="${CLAUDE_USAGE_CACHE_TTL:-300}"
CACHE_FILE="/tmp/claude-usage-bar-cache"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-usage/config"
CREDS_FILE="${CLAUDE_CREDENTIALS_FILE:-$HOME/.claude/.credentials.json}"

# Load config file if exists (overrides env vars)
if [[ -f "$CONFIG_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    case "$key" in
      style) BAR_STYLE="$value" ;;
      display) DISPLAY_MODE="$value" ;;
      format) FORMAT="$value" ;;
      width) BAR_WIDTH="$value" ;;
    esac
  done < "$CONFIG_FILE"
fi

# Create progress bar with time marker
make_bar() {
  local usage=$1
  local time_pct=$2
  local width=$3
  local label=$4

  local filled=$((usage * width / 100))
  local time_pos=$((time_pct * width / 100))

  [[ $filled -gt $width ]] && filled=$width
  [[ $filled -lt 0 ]] && filled=0
  [[ $time_pos -gt $width ]] && time_pos=$width
  [[ $time_pos -lt 0 ]] && time_pos=0

  local bar=""

  case "$BAR_STYLE" in
    ascii)
      for ((i=0; i<width; i++)); do
        if [[ $i -eq $time_pos ]]; then
          bar+="|"
        elif [[ $i -lt $filled ]]; then
          bar+="#"
        else
          bar+="."
        fi
      done
      echo "$label[$bar]"
      ;;
    braille)
      local total_dots=$((width * 8))
      local filled_dots=$((usage * total_dots / 100))
      for ((i=0; i<width; i++)); do
        local char_dots=$((filled_dots - i * 8))
        [[ $char_dots -lt 0 ]] && char_dots=0
        [[ $char_dots -gt 8 ]] && char_dots=8
        case $char_dots in
          0) bar+="⡀" ;;
          1) bar+="⣀" ;;
          2) bar+="⣄" ;;
          3) bar+="⣤" ;;
          4) bar+="⣦" ;;
          5) bar+="⣶" ;;
          6) bar+="⣷" ;;
          7|8) bar+="⣿" ;;
        esac
      done
      echo "$label$bar"
      ;;
    unicode|*)
      for ((i=0; i<width; i++)); do
        if [[ $i -eq $time_pos ]]; then
          bar+="│"
        elif [[ $i -lt $filled ]]; then
          bar+="█"
        else
          bar+="░"
        fi
      done
      echo "$label[$bar]"
      ;;
  esac
}

# Format time remaining
format_time_remaining() {
  local reset_time=$1
  local now=$(date +%s)
  local reset_epoch=$(date -d "$reset_time" +%s 2>/dev/null || echo 0)
  local remaining=$((reset_epoch - now))

  if [[ $remaining -lt 0 ]]; then
    echo "now"
  elif [[ $remaining -lt 3600 ]]; then
    echo "$((remaining / 60))m"
  elif [[ $remaining -lt 86400 ]]; then
    echo "$((remaining / 3600))h"
  else
    echo "$((remaining / 86400))d"
  fi
}

# Output error JSON
error_json() {
  echo "{\"text\": \"?\", \"tooltip\": \"$1\", \"class\": \"error\"}"
  exit 0
}

# Check cache first (but not if config changed)
config_hash=""
[[ -f "$CONFIG_FILE" ]] && config_hash=$(md5sum "$CONFIG_FILE" 2>/dev/null | cut -d' ' -f1)
cache_valid=false
if [[ -f "$CACHE_FILE" ]]; then
  cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  cached_hash=$(head -1 "$CACHE_FILE" 2>/dev/null | grep "^#hash:" | cut -d: -f2)
  if [[ $cache_age -lt $CACHE_TTL && "$cached_hash" == "$config_hash" ]]; then
    tail -n +2 "$CACHE_FILE"
    exit 0
  fi
fi

# Verify credentials exist
if [[ ! -f "$CREDS_FILE" ]]; then
  error_json "Claude credentials not found"
fi

# Extract OAuth token
token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDS_FILE" 2>/dev/null)
if [[ -z "$token" ]]; then
  error_json "No OAuth token found"
fi

# Fetch usage data from Anthropic API
response=$(curl -s --max-time 10 \
  -H "Authorization: Bearer $token" \
  -H "anthropic-beta: oauth-2025-04-20" \
  "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

if [[ -z "$response" ]] || echo "$response" | jq -e '.error' >/dev/null 2>&1; then
  error_json "Failed to fetch usage data"
fi

# Parse usage values
five_hour=$(echo "$response" | jq -r '.five_hour.utilization // 0' | cut -d. -f1)
seven_day=$(echo "$response" | jq -r '.seven_day.utilization // 0' | cut -d. -f1)
sonnet=$(echo "$response" | jq -r '.seven_day_sonnet.utilization // 0' | cut -d. -f1)
five_hour_full=$(echo "$response" | jq -r '.five_hour.utilization // 0')
seven_day_full=$(echo "$response" | jq -r '.seven_day.utilization // 0')
sonnet_full=$(echo "$response" | jq -r '.seven_day_sonnet.utilization // 0')
five_hour_reset=$(echo "$response" | jq -r '.five_hour.resets_at // empty')
seven_day_reset=$(echo "$response" | jq -r '.seven_day.resets_at // empty')

# Calculate time progress through windows
now=$(date +%s)

if [[ -n "$five_hour_reset" && "$five_hour_reset" != "null" ]]; then
  reset_epoch=$(date -d "$five_hour_reset" +%s 2>/dev/null || echo 0)
  secs_until_reset=$((reset_epoch - now))
  secs_into_window=$((18000 - secs_until_reset))
  five_hour_time_pct=$((secs_into_window * 100 / 18000))
  [[ $five_hour_time_pct -lt 0 ]] && five_hour_time_pct=0
  [[ $five_hour_time_pct -gt 100 ]] && five_hour_time_pct=100
  five_hour_reset_fmt=$(date -d "$five_hour_reset" "+%H:%M" 2>/dev/null || echo "--:--")
  five_hour_remaining=$(format_time_remaining "$five_hour_reset")
else
  five_hour_time_pct=0
  five_hour_reset_fmt="--:--"
  five_hour_remaining="--"
fi

if [[ -n "$seven_day_reset" && "$seven_day_reset" != "null" ]]; then
  reset_epoch=$(date -d "$seven_day_reset" +%s 2>/dev/null || echo 0)
  secs_until_reset=$((reset_epoch - now))
  secs_into_window=$((604800 - secs_until_reset))
  seven_day_time_pct=$((secs_into_window * 100 / 604800))
  [[ $seven_day_time_pct -lt 0 ]] && seven_day_time_pct=0
  [[ $seven_day_time_pct -gt 100 ]] && seven_day_time_pct=100
  seven_day_reset_fmt=$(date -d "$seven_day_reset" "+%b %d" 2>/dev/null || echo "--")
  seven_day_remaining=$(format_time_remaining "$seven_day_reset")
else
  seven_day_time_pct=0
  seven_day_reset_fmt="--"
  seven_day_remaining="--"
fi

# Build progress bars
bar_5h=$(make_bar "$five_hour" "$five_hour_time_pct" "$BAR_WIDTH" "5h")
bar_7d=$(make_bar "$seven_day" "$seven_day_time_pct" "$BAR_WIDTH" "7d")
bar_sn=$(make_bar "$sonnet" "$seven_day_time_pct" "$BAR_WIDTH" "S")

# Build text based on display mode and format
case "$FORMAT" in
  percent)
    case "$DISPLAY_MODE" in
      5h) text="5h:${five_hour}%" ;;
      7d) text="7d:${seven_day}%" ;;
      minimal) text="${five_hour}/${seven_day}%" ;;
      all|*) text="5h:${five_hour}% 7d:${seven_day}% S:${sonnet}%" ;;
    esac
    ;;
  time)
    case "$DISPLAY_MODE" in
      5h) text="5h:${five_hour_remaining}" ;;
      7d) text="7d:${seven_day_remaining}" ;;
      minimal) text="${five_hour_remaining}/${seven_day_remaining}" ;;
      all|*) text="5h:${five_hour_remaining} 7d:${seven_day_remaining}" ;;
    esac
    ;;
  bars|*)
    case "$DISPLAY_MODE" in
      5h) text="$bar_5h" ;;
      7d) text="$bar_7d" ;;
      minimal) text="${five_hour}%|${seven_day}%" ;;
      all|*) text="$bar_5h $bar_7d $bar_sn" ;;
    esac
    ;;
esac

# Determine class based on usage thresholds
if [[ $five_hour -ge 80 ]] || [[ $seven_day -ge 80 ]]; then
  class="critical"
elif [[ $five_hour -ge 50 ]] || [[ $seven_day -ge 50 ]]; then
  class="warning"
else
  class="normal"
fi

# Build tooltip with current config info
tooltip="Claude Usage\\n━━━━━━━━━━━━━━━━━━━━\\n"
tooltip+="5hr: ${five_hour_full}% (resets $five_hour_reset_fmt, ${five_hour_remaining})\\n"
tooltip+="7d:  ${seven_day_full}% (resets $seven_day_reset_fmt, ${seven_day_remaining})\\n"
tooltip+="Sonnet 7d: ${sonnet_full}%\\n\\n"
tooltip+="Style: $BAR_STYLE | Display: $DISPLAY_MODE | Format: $FORMAT\\n"
tooltip+="Scroll to change style, Ctrl+Scroll for display"

# Output JSON
result="{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
{
  echo "#hash:$config_hash"
  echo "$result"
} > "$CACHE_FILE"
echo "$result"
