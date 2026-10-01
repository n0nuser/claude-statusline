# claude-statusline

A 2-line status bar for [Claude Code](https://claude.com/claude-code), showing model/effort, context usage, and rate limits at a glance.

## Preview

![statusline preview](screenshot.png)

## Layout

```
Opus 5 (medium) | 0 ░░░░░░░░░░ 1.0m (0%)
window 5h 0% (3h12m) · week 0%
```

1. **Model + effort | context bar**: used tokens, a 10-cell bar, total context window, and % used
2. **window 5h | week**: 5-hour and 7-day rate limit usage, with a countdown to when the 5-hour window resets

Percentages and the context bar are color-coded: green (<50%) → yellow (≥50%) → orange (≥70%) → red (≥90%).

Line 2 is omitted when Claude Code supplies no rate-limit data.

## Install

```bash
git clone https://github.com/n0nuser/claude-statusline.git ~/.claude/claude-statusline
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "jq -nrj -f ~/.claude/claude-statusline/statusline.jq"
  }
}
```

On Windows, use full paths, e.g. `"C:/path/to/jq.exe" -nrj -f "C:/Users/<you>/.claude/claude-statusline/statusline.jq"`.

Restart Claude Code (or start a new session) to pick up the change.

It is a single `jq` program (no shell, no subprocesses), since the status line runs on every refresh of every session.

## Requirements

- `jq` (1.6+)
- A terminal with 256-color support

## Update

```bash
cd ~/.claude/claude-statusline && git pull
```

## License

MIT
