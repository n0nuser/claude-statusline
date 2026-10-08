# Status line, 2 lines:
#  1) model+effort | context bar
#  2) window (5h) usage | week (7d) usage
#
# Run as: jq -nrj -f statusline.jq
# Pure jq, so each refresh starts one native process and no shell: process
# creation is slow on Windows/Git Bash, especially with endpoint scanning.

def esc(c): "\u001b[" + c + "m";
def reset: esc("0");
def dim: esc("2");
def model_c: esc("38;5;81");    # cyan - model
def effort_c: esc("38;5;141");  # purple - effort
def label_c: esc("38;5;208");   # orange - usage labels

def usage_color:
    if . >= 90 then esc("38;5;196")    # red
    elif . >= 70 then esc("38;5;208")  # orange
    elif . >= 50 then esc("38;5;220")  # yellow
    else esc("38;5;114")               # green
    end;

# "x" * 0 is null in jq < 1.8, so guard the zero case.
def rep(s): if . > 0 then s * . else "" end;

def fmt_tokens:
    if . >= 1000000 then ((. + 50000) / 100000 | floor) as $t | "\($t / 10 | floor).\($t % 10)m"
    elif . >= 1000 then "\((. + 500) / 1000 | floor)k"
    else "\(.)"
    end;

def fmt_countdown:
    (if . < 0 then 0 else . end) as $s
    | ($s / 3600 | floor) as $h
    | (($s % 3600) / 60 | floor) as $m
    | if $h > 0 then "\($h)h\(if $m < 10 then "0" else "" end)\($m)m" else "\($m)m" end;

# Weekly reset: days, or hours (with minutes) when under a day.
def fmt_countdown_days:
    (if . < 0 then 0 else . end) as $s
    | ($s / 3600 | floor) as $h
    | if $h >= 24 then "\($h / 24 | floor)d\($h % 24)h"
      elif $h > 0 then "\($h)h\(if ($s % 3600) / 60 | floor < 10 then "0" else "" end)\(($s % 3600) / 60 | floor)m"
      else "\(($s % 3600) / 60 | floor)m"
      end;

def whole: if type == "number" then floor else null end;
def pct: if type == "number" then . + 0.5 | floor else null end;

# No input (or unparseable): emit a bare label rather than a broken line.
(try input catch null) as $in
| if ($in | type) != "object" then "Claude" else $in |

# ---- model + effort ----
(.model.display_name // "Claude") as $model
| (.effort.level // "") as $effort
| (model_c + "\($model)" + reset
   + if $effort != "" then " " + effort_c + "(\($effort))" + reset else "" end) as $model_seg

# ---- context window bar ----
| (.context_window.context_window_size | whole | if . == null or . <= 0 then 200000 else . end) as $size
| (.context_window.total_input_tokens | whole | if . == null or . < 0 then 0 else . end) as $used
| ($used * 100 / $size | floor | if . > 100 then 100 else . end) as $p
| ($p * 10 / 100 | floor) as $filled
| ($p | usage_color) as $ctx_color
| ("\($used | fmt_tokens) " + $ctx_color + ($filled | rep("▓")) + (10 - $filled | rep("░")) + reset
   + " \($size | fmt_tokens) " + dim + "(\($p)%)" + reset) as $ctx_seg

# ---- usage windows (5h + 7d) ----
| (.rate_limits.five_hour.used_percentage | pct) as $five
| (.rate_limits.five_hour.resets_at | whole) as $resets
| (if $five == null then ""
   else label_c + "window 5h" + reset + " " + ($five | usage_color) + "\($five)%" + reset
     + if $resets == null then ""
       else " " + dim + "(" + reset + label_c + ($resets - (now | floor) | fmt_countdown) + reset + dim + ")" + reset
       end
   end) as $window_seg
| (.rate_limits.seven_day.used_percentage | pct) as $seven
| (.rate_limits.seven_day.resets_at | whole) as $week_resets
| (if $seven == null then ""
   else label_c + "week" + reset + " " + ($seven | usage_color) + "\($seven)%" + reset
     + if $week_resets == null then ""
       else " " + dim + "(" + reset + label_c + ($week_resets - (now | floor) | fmt_countdown_days) + reset + dim + ")" + reset
       end
   end) as $week_seg

# ---- assemble (2 lines) ----
| (if $window_seg != "" and $week_seg != "" then $window_seg + " " + dim + "·" + reset + " " + $week_seg
   else $window_seg + $week_seg
   end) as $line2
| $model_seg + " " + dim + "|" + reset + " " + $ctx_seg
  + if $line2 != "" then "\n" + $line2 else "" end
end
