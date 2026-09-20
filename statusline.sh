#!/bin/bash
# Status line, 2 lines:
#  1) model+effort | context bar
#  2) window (5h) usage | week (7d) usage

input=$(cat)

# No input (or unparseable): emit a bare label rather than a broken line.
if [ -z "$input" ] || ! echo "$input" | jq -e . >/dev/null 2>&1; then
    printf "Claude"
    exit 0
fi

# ---- colors ----
dim='\033[2m'
reset='\033[0m'
model_c='\033[38;5;81m'       # cyan - model
effort_c='\033[38;5;141m'     # purple - effort
label_c='\033[38;5;208m'      # orange - usage labels

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

fmt_countdown() {
    local secs=$1
    [ "$secs" -lt 0 ] && secs=0
    local h=$(( secs / 3600 ))
    local m=$(( (secs % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then printf "%dh%02dm" "$h" "$m"
    else printf "%dm" "$m"; fi
}

# ---- model + effort ----
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
effort=$(echo "$input" | jq -r '.effort.level // empty')
model_seg="${model_c}${model_name}${reset}"
[ -n "$effort" ] && model_seg+=" ${effort_c}(${effort})${reset}"

# ---- context window bar ----
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
ctx_used=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
case "$ctx_size" in ''|*[!0-9]*) ctx_size=200000 ;; esac
case "$ctx_used" in ''|*[!0-9]*) ctx_used=0 ;; esac
[ "$ctx_size" -le 0 ] && ctx_size=200000
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

# ---- usage windows (5h + 7d) ----
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
window_seg=""
if [ -n "$five_pct" ]; then
    five_pct_i=$(printf '%.0f' "$five_pct")
    five_color=$(usage_color "$five_pct_i")
    window_seg="${label_c}window 5h${reset} ${five_color}${five_pct_i}%${reset}"

    five_resets_at=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    if [ -n "$five_resets_at" ]; then
        now=$(date +%s)
        remaining=$(( five_resets_at - now ))
        window_seg="${window_seg} ${dim}(${reset}${label_c}$(fmt_countdown "$remaining")${reset}${dim})${reset}"
    fi
fi

seven_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_seg=""
if [ -n "$seven_pct" ]; then
    seven_pct_i=$(printf '%.0f' "$seven_pct")
    seven_color=$(usage_color "$seven_pct_i")
    week_seg="${label_c}week${reset} ${seven_color}${seven_pct_i}%${reset}"
fi

# ---- git branch (only inside a git repo) ----
branch_c='\033[38;5;114m'    # green - git branch
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
branch_seg=""
if [ -n "$cwd" ] && branch=$(git -C "$cwd" branch --show-current 2>/dev/null) && [ -n "$branch" ]; then
    branch_seg="${branch_c}🌿 ${branch}${reset}"
fi

# ---- assemble (2 lines) ----
line1="${model_seg}${sep}${ctx_seg}"

line2=""
if [ -n "$window_seg" ] && [ -n "$week_seg" ]; then
    line2="${window_seg} ${dim}·${reset} ${week_seg}"
else
    line2="${window_seg}${week_seg}"
fi
[ -n "$branch_seg" ] && [ -n "$line2" ] && line2="${branch_seg} ${dim}|${reset} ${line2}"

out="$line1"
[ -n "$line2" ] && out+=$'\n'"$line2"

printf "%b" "$out"
