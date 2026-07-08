# claude-statusline

A 3-line status bar for [Claude Code](https://claude.com/claude-code), showing model/effort, context usage, cost, git state, and rate limits at a glance.

## Preview

![statusline preview](screenshot.png)

## Layout

1. **Model + effort | context bar | cost | 5h session usage**
2. **Git**: branch, staged/unstaged counts, lines +/-, clickable repo link, PR badge (with review state), 🔥 fire warning past 200k tokens
3. **Wall time / API time | 7-day usage**

## Install

```bash
git clone https://github.com/n0nuser/claude-statusline.git ~/.claude/claude-statusline
chmod +x ~/.claude/claude-statusline/statusline.sh
```

Add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/claude-statusline/statusline.sh"
  }
}
```

Restart Claude Code (or start a new session) to pick up the change.

## Requirements

- `bash`, `jq`, `git`
- A terminal with 256-color and OSC 8 hyperlink support (iTerm2, Kitty, WezTerm) to get clickable repo/PR links. Falls back to plain text elsewhere.

## Update

```bash
cd ~/.claude/claude-statusline && git pull
```

## License

MIT
