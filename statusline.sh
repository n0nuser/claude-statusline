#!/bin/bash
# Status line, 3 lines:
#  1) model+effort | context bar | cost | session (5h) usage + reset
#  2) git: branch, staged/unstaged, lines +/-, repo link, PR badge, 200k-fire warning
#  3) wall/api time | 7d usage

input=$(cat)

# ---- colors ----
dim='\033[2m'
reset='\033[0m'
model_c='\033[38;5;81m'       # cyan - model
effort_c='\033[38;5;141m'     # purple - effort
cost_c='\033[38;5;114m'       # green - cost/time group
git_branch_c='\033[38;5;141m' # purple - branch
staged_c='\033[38;5;34m'      # green - staged
unstaged_c='\033[38;5;196m'   # red - unstaged
usage_c='\033[38;5;208m'      # orange - session usage %

sep=" ${dim}|${reset} "

usage_color() {
    local pct=$1
    if [ "$pct" -ge 90 ]; then echo '\033[38;5;196m'   # red
    elif [ "$pct" -ge 70 ]; then echo '\033[38;5;208m' # orange
    elif [ "$pct" -ge 50 ]; then echo '\033[38;5;220m' # yellow
    else echo '\033[38;5;114m'                          # green
    fi
}

fmt_tokens() {
    local n=$1
    if [ "$n" -ge 1000000 ]; then awk "BEGIN{printf \"%.1fm\", $n/1000000}"
    elif [ "$n" -ge 1000 ]; then awk "BEGIN{printf \"%.0fk\", $n/1000}"
    else printf "%d" "$n"; fi
}

fmt_hms() {
    local ms=$1
    local sec=$((ms / 1000))
    local h=$((sec / 3600))
    local m=$(((sec % 3600) / 60))
    local s=$((sec % 60))
    if [ "$h" -gt 0 ]; then printf "%dh%dm" "$h" "$m"
    elif [ "$m" -gt 0 ]; then printf "%dm%ds" "$m" "$s"
    else printf "%ds" "$s"; fi
}

# ---- model + effort ----
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
model_seg="${model_c}${model_name}${reset}"
[ -n "$effort" ] && model_seg+=" ${effort_c}(${effort})${reset}"

# ---- context window bar ----
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
ctx_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
[ "$ctx_size" -le 0 ] 2>/dev/null && ctx_size=200000
pct=$(( ctx_used * 100 / ctx_size ))
[ "$pct" -gt 100 ] && pct=100
bar_width=10
filled=$(( pct * bar_width / 100 ))
empty=$(( bar_width - filled ))
bar=""
[ "$filled" -gt 0 ] && printf -v fill "%${filled}s" && bar="${fill// /▓}"
[ "$empty" -gt 0 ] && printf -v pad "%${empty}s" && bar="${bar}${pad// /░}"
ctx_color=$(usage_color "$pct")
used_fmt=$(fmt_tokens "$ctx_used")
size_fmt=$(fmt_tokens "$ctx_size")
ctx_seg="${used_fmt} ${ctx_color}${bar}${reset} ${size_fmt} ${dim}(${pct}%)${reset}"

exceeds=$(echo "$input" | jq -r '.exceeds_200k_tokens // false')
[ "$exceeds" = "true" ] && ctx_seg="🔥 ${ctx_seg} 🔥"

# ---- cost / time ----
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
cost_fmt=$(printf '$%.2f' "$cost")
dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
api_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
dur_fmt=$(fmt_hms "$dur_ms")
api_fmt=$(fmt_hms "$api_ms")
lines_added=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
lines_removed=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')

# ---- session usage (5h + 7d) ----
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
usage_seg=""
if [ -n "$five_pct" ]; then
    five_pct_i=$(printf '%.0f' "$five_pct")
    five_color=$(usage_color "$five_pct_i")
    usage_seg="${usage_c}5h${reset} ${five_color}${five_pct_i}%${reset}"
    if [ -n "$five_reset" ] && [ "$five_reset" != "null" ]; then
        now_epoch=$(date +%s)
        remain_sec=$(( five_reset - now_epoch ))
        [ "$remain_sec" -lt 0 ] && remain_sec=0
        remain_h=$(( remain_sec / 3600 ))
        remain_m=$(( (remain_sec % 3600) / 60 ))
        usage_seg="${usage_seg} ${dim}(${remain_h}h${remain_m}m left)${reset}"
    fi
fi

seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_seg=""
if [ -n "$seven_pct" ]; then
    seven_pct_i=$(printf '%.0f' "$seven_pct")
    seven_color=$(usage_color "$seven_pct_i")
    seven_seg="${usage_c}7d${reset} ${seven_color}${seven_pct_i}%${reset}"
fi

# ---- git (cached — numstat diffs are slow on big repos) ----
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
session_id=$(echo "$input" | jq -r '.session_id // "nosession"')
git_seg=""
if [ -n "$cwd" ]; then
    cache_file="/tmp/claude-statusline-git-${session_id}"
    cache_max_age=5
    stale=true
    if [ -f "$cache_file" ]; then
        mtime=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0)
        age=$(( $(date +%s) - mtime ))
        [ "$age" -lt "$cache_max_age" ] && stale=false
    fi

    if $stale; then
        if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
            branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
            staged=$(git -C "$cwd" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
            unstaged=$(git -C "$cwd" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
            printf '%s|%s|%s\n' "$branch" "$staged" "$unstaged" > "$cache_file"
        else
            printf '||\n' > "$cache_file"
        fi
    fi

    IFS='|' read -r branch staged unstaged < "$cache_file"

    if [ -n "$branch" ]; then
        git_seg="🌿 ${git_branch_c}${branch}${reset}"
        [ "$staged" -gt 0 ] && git_seg="${git_seg}${sep}📥 ${staged_c}+${staged}${reset}"
        [ "$unstaged" -gt 0 ] && git_seg="${git_seg}${sep}📝 ${unstaged_c}~${unstaged}${reset}"
        if [ "$lines_added" -gt 0 ] || [ "$lines_removed" -gt 0 ]; then
            git_seg="${git_seg}${sep}${staged_c}+${lines_added}${reset}/${unstaged_c}-${lines_removed}${reset}"
        fi

        repo_host=$(echo "$input" | jq -r '.workspace.repo.host // empty')
        repo_owner=$(echo "$input" | jq -r '.workspace.repo.owner // empty')
        repo_name=$(echo "$input" | jq -r '.workspace.repo.name // empty')
        if [ -n "$repo_host" ] && [ -n "$repo_owner" ] && [ -n "$repo_name" ]; then
            repo_url="https://${repo_host}/${repo_owner}/${repo_name}"
            git_seg="${git_seg}${sep}\033]8;;${repo_url}\a📦 ${repo_name}\033]8;;\a"
        fi

        pr_number=$(echo "$input" | jq -r '.pr.number // empty')
        if [ -n "$pr_number" ]; then
            pr_state=$(echo "$input" | jq -r '.pr.review_state // empty')
            case "$pr_state" in
                approved)          pr_emoji="✅" ;;
                changes_requested) pr_emoji="❌" ;;
                pending)           pr_emoji="⏳" ;;
                draft)             pr_emoji="📝" ;;
                *)                 pr_emoji="🔀" ;;
            esac
            pr_url=$(echo "$input" | jq -r '.pr.url // empty')
            if [ -n "$pr_url" ]; then
                git_seg="${git_seg}${sep}\033]8;;${pr_url}\a${pr_emoji} #${pr_number}\033]8;;\a"
            else
                git_seg="${git_seg}${sep}${pr_emoji} #${pr_number}"
            fi
        fi
    fi
fi

# ---- assemble (3 lines) ----
line1="${model_seg}"
line1+="${sep}${ctx_seg}"
line1+="${sep}${cost_c}${cost_fmt}${reset}"
[ -n "$usage_seg" ] && line1+="${sep}${usage_seg}"

line2="$git_seg"

line3="${dim}wall:${reset}${cost_c}${dur_fmt}${reset}"
line3+="${sep}${dim}api:${reset}${cost_c}${api_fmt}${reset}"
[ -n "$seven_seg" ] && line3+="${sep}${seven_seg}"

out="$line1"
[ -n "$line2" ] && out+=$'\n'"$line2"
out+=$'\n'"$line3"

printf "%b" "$out"
