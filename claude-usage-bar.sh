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
#   CLAUDE_USAGE_BAR_STYLE  - Bar style: unicode, ascii, braille, minimal (default: unicode)
#   CLAUDE_USAGE_DISPLAY    - Display mode: all, 5h, 7d, sonnet (default: all)
#   CLAUDE_USAGE_CACHE_TTL  - Cache TTL in seconds (default: 5)
#   CLAUDE_CREDENTIALS_FILE - Path to credentials (default: ~/.claude/.credentials.json)
#
# Config file: ~/.config/claude-usage/config (overrides env vars)
#   style=unicode
#   display=all

set -euo pipefail

# Configuration defaults
BAR_WIDTH="${CLAUDE_USAGE_BAR_WIDTH:-8}"
BAR_STYLE="${CLAUDE_USAGE_BAR_STYLE:-unicode}"
DISPLAY_MODE="${CLAUDE_USAGE_DISPLAY:-all}"
CACHE_TTL="${CLAUDE_USAGE_CACHE_TTL:-5}"
API_CACHE_FILE="/tmp/claude-usage-api-cache"
CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/claude-usage/config"
CREDS_FILE="${CLAUDE_CREDENTIALS_FILE:-$HOME/.claude/.credentials.json}"

# Load config file if exists (overrides env vars)
if [[ -f "$CONFIG_FILE" ]]; then
  while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^# ]] && continue
    case "$key" in
      style) BAR_STYLE="$value" ;;
      display) DISPLAY_MODE="$value" ;;
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

# Render output from API data
render_output() {
  local response="$1"

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

  # Build progress bars or minimal display based on style
  if [[ "$BAR_STYLE" == "minimal" ]]; then
    # Minimal style: just percentages
    case "$DISPLAY_MODE" in
      5h) text="${five_hour}%" ;;
      7d) text="${seven_day}%" ;;
      sonnet) text="${sonnet}%" ;;
      all|*) text="${five_hour}%│${seven_day}%│${sonnet}%" ;;
    esac
  else
    # Bar styles: unicode, ascii, braille
    bar_5h=$(make_bar "$five_hour" "$five_hour_time_pct" "$BAR_WIDTH" "5h")
    bar_7d=$(make_bar "$seven_day" "$seven_day_time_pct" "$BAR_WIDTH" "7d")
    bar_sn=$(make_bar "$sonnet" "$seven_day_time_pct" "$BAR_WIDTH" "So")

    case "$DISPLAY_MODE" in
      5h) text="$bar_5h" ;;
      7d) text="$bar_7d" ;;
      sonnet) text="$bar_sn" ;;
      all|*) text="$bar_5h $bar_7d $bar_sn" ;;
    esac
  fi

  # Determine class based on usage thresholds
  if [[ $five_hour -ge 80 ]] || [[ $seven_day -ge 80 ]]; then
    class="critical"
  elif [[ $five_hour -ge 50 ]] || [[ $seven_day -ge 50 ]]; then
    class="warning"
  else
    class="normal"
  fi

  # Calculate precise time-to-reset values with right-aligned spacing
  if [[ -n "$five_hour_reset" && "$five_hour_reset" != "null" ]]; then
    five_hour_reset_time=$(date -d "$five_hour_reset" "+%H:%M" 2>/dev/null || echo "--:--")
    five_hour_reset_date=$(date -d "$five_hour_reset" "+%b %d" 2>/dev/null || echo "--")
  else
    five_hour_reset_time="--:--"
    five_hour_reset_date="--"
  fi

  if [[ -n "$seven_day_reset" && "$seven_day_reset" != "null" ]]; then
    seven_day_reset_time=$(date -d "$seven_day_reset" "+%H:%M" 2>/dev/null || echo "--:--")
    seven_day_reset_date=$(date -d "$seven_day_reset" "+%b %d" 2>/dev/null || echo "--")
  else
    seven_day_reset_time="--:--"
    seven_day_reset_date="--"
  fi

  # Build tooltip with right-aligned time-to-reset
  tooltip="Claude Usage\\n━━━━━━━━━━━━━━━━━━━━\\n"
  tooltip+="5hrs:     ${five_hour_full}% │ $(printf '%4s' "$five_hour_remaining") ($five_hour_reset_time $five_hour_reset_date)\\n"
  tooltip+="7day:     ${seven_day_full}% │ $(printf '%4s' "$seven_day_remaining") ($seven_day_reset_time $seven_day_reset_date)\\n"
  tooltip+="Snnt:     ${sonnet_full}% │ $(printf '%4s' "$seven_day_remaining") ($seven_day_reset_time $seven_day_reset_date)\\n\\n"
  tooltip+="Style: $BAR_STYLE | Display: $DISPLAY_MODE\\n"
  tooltip+="Mid=style, Scroll=display, Right=refresh, Left=web"

  echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
}

# Check API cache - use cached API data if fresh enough
response=""
if [[ -f "$API_CACHE_FILE" ]]; then
  cache_age=$(($(date +%s) - $(stat -c %Y "$API_CACHE_FILE" 2>/dev/null || echo 0)))
  if [[ $cache_age -lt $CACHE_TTL ]]; then
    response=$(cat "$API_CACHE_FILE" 2>/dev/null)
  fi
fi

# Fetch fresh API data if cache is stale or missing
if [[ -z "$response" ]]; then
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

  # Cache the API response
  echo "$response" > "$API_CACHE_FILE"
fi

# Render and output
render_output "$response"
