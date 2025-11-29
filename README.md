# Claude Usage Monitor

Display your Claude Pro/Max subscription usage in your terminal statusline or desktop bar.

```
5h[████████│░░░░░░░░░░░░░░░░░░░░░] 7d[████████░░░░░░░░░░░│░░░░░░░░░] S[█░░░░░░░░░░░░░░░░░░│░░░░░░░░░]
```

**Features:**
- ASCII progress bars showing usage percentage
- Time markers (│) showing position in rolling windows
- Support for 5-hour, 7-day, and Sonnet-specific quotas
- Works with Claude Code statusline, Waybar, Hyprpanel, and other bars
- Caching to minimize API calls

## How It Works

Claude Pro and Max subscriptions have rolling usage windows:
- **5-hour window**: Short-term rate limit
- **7-day window**: Weekly usage cap
- **Sonnet quota**: Separate allowance for Claude Sonnet

The progress bars show:
- `█` = Usage consumed
- `░` = Remaining allowance
- `│` = Current position in the time window

When the time marker catches up to your usage, your quota resets!

## Prerequisites

- [Claude Code](https://claude.ai/code) with OAuth authentication (requires Pro/Max subscription)
- `curl` and `jq` installed

## Quick Install

```bash
curl -sL https://raw.githubusercontent.com/KaiStarkk/claude-usage-monitor/main/install.sh | bash
```

Or manually:

```bash
mkdir -p ~/.local/bin
curl -sL https://raw.githubusercontent.com/KaiStarkk/claude-usage-monitor/main/claude-usage-statusline.sh -o ~/.local/bin/claude-usage-statusline.sh
curl -sL https://raw.githubusercontent.com/KaiStarkk/claude-usage-monitor/main/claude-usage-bar.sh -o ~/.local/bin/claude-usage-bar.sh
chmod +x ~/.local/bin/claude-usage-*.sh
```

## Integration

### Claude Code Statusline

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/claude-usage-statusline.sh",
    "padding": 0
  }
}
```

Or use the `/statusline` command in Claude Code to configure interactively.

### Waybar

Add to your waybar config:

```jsonc
{
  "modules-right": ["custom/claude-usage", "clock"],

  "custom/claude-usage": {
    "exec": "~/.local/bin/claude-usage-bar.sh",
    "return-type": "json",
    "interval": 60,
    "tooltip": true,
    "on-click": "xdg-open https://claude.ai/settings/usage",
    "on-click-right": "rm -f /tmp/claude-usage-bar-cache"
  }
}
```

Add styling to `style.css`:

```css
#custom-claude-usage {
  font-family: "FiraCode Nerd Font", monospace;
}
#custom-claude-usage.warning { color: #f9e2af; }
#custom-claude-usage.critical { color: #f38ba8; }
```

### Hyprpanel

Add to your `modules.json`:

```json
{
  "custom/claude-usage": {
    "icon": "󰚩",
    "execute": "~/.local/bin/claude-usage-bar.sh",
    "label": "{text}",
    "tooltip": "{tooltip}",
    "interval": 60000,
    "actions": {
      "onLeftClick": "xdg-open https://claude.ai/settings/usage",
      "onRightClick": "rm -f /tmp/claude-usage-bar-cache"
    }
  }
}
```

Then add `"custom/claude-usage"` to your bar layout in `config.json`.

### Nix / Home Manager

```nix
{ pkgs, ... }: {
  home.file."bin/claude-usage-statusline.sh" = {
    executable = true;
    source = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/KaiStarkk/claude-usage-monitor/main/claude-usage-statusline.sh";
      sha256 = ""; # nix-prefetch-url will give you this
    };
  };
}
```

## Configuration

Environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_USAGE_BAR_WIDTH` | 30 (statusline) / 8 (bar) | Width of progress bars |
| `CLAUDE_USAGE_CACHE_TTL` | 600 (statusline) / 300 (bar) | Cache duration in seconds |
| `CLAUDE_CREDENTIALS_FILE` | `~/.claude/.credentials.json` | Path to Claude Code credentials |

## API Details

This tool uses the Anthropic OAuth usage endpoint:

```
GET https://api.anthropic.com/api/oauth/usage
Headers:
  Authorization: Bearer <oauth_token>
  anthropic-beta: oauth-2025-04-20
```

Returns:
```json
{
  "five_hour": {"utilization": 45.0, "resets_at": "2025-01-15T10:00:00Z"},
  "seven_day": {"utilization": 28.0, "resets_at": "2025-01-20T10:00:00Z"},
  "seven_day_sonnet": {"utilization": 5.0, "resets_at": "2025-01-20T10:00:00Z"}
}
```

The OAuth token is obtained automatically when you authenticate Claude Code.

## Troubleshooting

**"no oauth token" error**
- Run `claude` and complete the authentication flow
- Check that `~/.claude/.credentials.json` exists and contains `claudeAiOauth.accessToken`

**Bars not updating**
- Clear the cache: `rm -f /tmp/claude-usage-*`
- Check API response: `~/.local/bin/claude-usage-bar.sh`

**Wrong time displayed**
- The scripts use your system timezone for reset time display
- Ensure your system clock is accurate

## Credits

- Inspired by [codelynx.dev's statusline guide](https://codelynx.dev/posts/claude-code-usage-limits-statusline)
- OAuth endpoint discovery from Claude Code reverse engineering

## License

MIT License - See [LICENSE](LICENSE) for details.
