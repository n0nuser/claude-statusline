#!/bin/bash
# Status line, 2 lines:
#  1) model+effort | context bar
#  2) branch | window (5h) usage | week (7d) usage
#
# Runs on every refresh of every session, so it spawns exactly one external
# process (jq). Everything else is bash builtins: process creation is slow on
# Windows/Git Bash, especially with endpoint scanning.

input=$(</dev/stdin)

# One jq call extracts every field, joined by \x1f. Not @tsv: tab is IFS
# whitespace, so `read` would collapse empty fields and shift the rest.
IFS=$'\x1f' read -r model_name effort ctx_size ctx_used five_pct five_resets_at seven_pct cwd < <(
    jq -r '
        def pct: if type == "number" then (. + 0.5 | floor | tostring) else "" end;
        [ (.model.display_name // "Claude"),
          (.effort.level // ""),
          (.context_window.context_window_size // 200000 | tostring),
          (.context_window.total_input_tokens // 0 | tostring),
          (.rate_limits.five_hour.used_percentage | pct),
          (.rate_limits.five_hour.resets_at // "" | tostring),
          (.rate_limits.seven_day.used_percentage | pct),
          (.workspace.current_dir // .cwd // "")
        ] | join("\u001f")' <<<"$input" 2>/dev/null
)

# No input (or unparseable): emit a bare label rather than a broken line.
if [ -z "$model_name" ]; then
    printf "Claude"
    exit 0
fi

# ---- colors ----
dim='\033[2m'
reset='\033[0m'
model_c='\033[38;5;81m'       # cyan - model
effort_c='\033[38;5;141m'     # purple - effort
label_c='\033[38;5;208m'      # orange - usage labels
branch_c='\033[38;5;114m'     # green - git branch

sep=" ${dim}|${reset} "

# Helpers write into the variable named by $1 (no $(...) subshells).
usage_color() {
    local pct=$2
    if [ "$pct" -ge 90 ]; then printf -v "$1" '%s' '\033[38;5;196m'   # red
    elif [ "$pct" -ge 70 ]; then printf -v "$1" '%s' '\033[38;5;208m' # orange
    elif [ "$pct" -ge 50 ]; then printf -v "$1" '%s' '\033[38;5;220m' # yellow
    else printf -v "$1" '%s' '\033[38;5;114m'                          # green
    fi
}

fmt_tokens() {
    local n=$2 t
    if [ "$n" -ge 1000000 ]; then
        t=$(( (n + 50000) / 100000 ))
        printf -v "$1" '%d.%dm' $(( t / 10 )) $(( t % 10 ))
    elif [ "$n" -ge 1000 ]; then printf -v "$1" '%dk' $(( (n + 500) / 1000 ))
    else printf -v "$1" '%d' "$n"; fi
}

fmt_countdown() {
    local secs=$2
    [ "$secs" -lt 0 ] && secs=0
    local h=$(( secs / 3600 ))
    local m=$(( (secs % 3600) / 60 ))
    if [ "$h" -gt 0 ]; then printf -v "$1" '%dh%02dm' "$h" "$m"
    else printf -v "$1" '%dm' "$m"; fi
}

# Branch from .git/HEAD (walks up; follows worktree/submodule `gitdir:` files).
git_branch() {
    local dir=${2//\\//} gitdir head
    printf -v "$1" '%s' ''
    while [ -n "$dir" ]; do
        if [ -d "$dir/.git" ]; then
            gitdir="$dir/.git"; break
        elif [ -f "$dir/.git" ]; then
            read -r gitdir < "$dir/.git" || return
            gitdir=${gitdir#gitdir: }
            gitdir=${gitdir//\\//}
            case "$gitdir" in /*|[A-Za-z]:/*) ;; *) gitdir="$dir/$gitdir" ;; esac
            break
        fi
        [ "$dir" = "${dir%/*}" ] && return
        dir=${dir%/*}
    done
    [ -n "$gitdir" ] && read -r head < "$gitdir/HEAD" 2>/dev/null || return
    case "$head" in ref:\ refs/heads/*) printf -v "$1" '%s' "${head#ref: refs/heads/}" ;; esac
}

# ---- model + effort ----
model_seg="${model_c}${model_name}${reset}"
[ -n "$effort" ] && model_seg+=" ${effort_c}(${effort})${reset}"

# ---- context window bar ----
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
usage_color ctx_color "$pct"
fmt_tokens used_fmt "$ctx_used"
fmt_tokens size_fmt "$ctx_size"
ctx_seg="${used_fmt} ${ctx_color}${bar}${reset} ${size_fmt} ${dim}(${pct}%)${reset}"

# ---- usage windows (5h + 7d) ----
window_seg=""
if [ -n "$five_pct" ]; then
    usage_color five_color "$five_pct"
    window_seg="${label_c}window 5h${reset} ${five_color}${five_pct}%${reset}"

    case "$five_resets_at" in
        ''|*[!0-9]*) ;;
        *)
            printf -v now '%(%s)T' -1
            fmt_countdown countdown $(( five_resets_at - now ))
            window_seg+=" ${dim}(${reset}${label_c}${countdown}${reset}${dim})${reset}"
            ;;
    esac
fi

week_seg=""
if [ -n "$seven_pct" ]; then
    usage_color seven_color "$seven_pct"
    week_seg="${label_c}week${reset} ${seven_color}${seven_pct}%${reset}"
fi

# ---- git branch (only inside a git repo) ----
branch_seg=""
if [ -n "$cwd" ]; then
    git_branch branch "$cwd"
    [ -n "$branch" ] && branch_seg="${branch_c}🌿 ${branch}${reset}"
fi

# ---- assemble (2 lines) ----
line1="${model_seg}${sep}${ctx_seg}"

if [ -n "$window_seg" ] && [ -n "$week_seg" ]; then
    line2="${window_seg} ${dim}·${reset} ${week_seg}"
else
    line2="${window_seg}${week_seg}"
fi
[ -n "$branch_seg" ] && [ -n "$line2" ] && line2="${branch_seg} ${dim}|${reset} ${line2}"

out="$line1"
[ -n "$line2" ] && out+=$'\n'"$line2"

printf "%b" "$out"
