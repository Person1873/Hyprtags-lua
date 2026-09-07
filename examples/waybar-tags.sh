#!/usr/bin/env bash
# hypr-dwm-land tag indicator for a bar that is not the Omarchy shell (waybar shown).
# Streams one JSON line per change, waybar "custom" module style:
#   {"text": "1 [2] 4", "class": "tags", "tooltip": "view 2 · occupied 1,2,4"}
# Occupied tags and viewed tags are listed; the viewed ones are bracketed; a tag holding
# the focused window is marked with *, an urgent tag with !. Tags 10..21 print as F1..F12.
#
# waybar config:
#   "custom/tags": { "exec": "~/.config/waybar/hypr-dwm-land-tags.sh", "return-type": "json",
#                    "on-click": "hyprctl eval 'hyprdwmland.view_next(1)'" }
# Only this monitor's line is used; pass the monitor name as $1 or it defaults to the
# first monitor. Untested with waybar itself; the parsing is exercised by running it
# and calling `hyprctl eval 'hyprdwmland.emit()'`.
set -euo pipefail
MON=${1:-$(/usr/bin/hyprctl monitors -j | /usr/bin/jq -r '.[0].name')}
SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
[[ -S $SOCK ]] || { echo "no Hyprland socket" >&2; exit 1; }

render() { # $1 = "eDP-1|v=2,3|o=1:2,2:1|u=|f=2"
  local line=$1 v o u f
  v=$(sed -n 's/.*|v=\([0-9,]*\).*/\1/p' <<<"$line")
  o=$(sed -n 's/.*|o=\([0-9:,]*\).*/\1/p' <<<"$line")
  u=$(sed -n 's/.*|u=\([0-9,]*\).*/\1/p' <<<"$line")
  f=$(sed -n 's/.*|f=\([0-9,]*\).*/\1/p' <<<"$line")
  declare -A viewed urgent focused occupied
  local k; for k in ${v//,/ }; do viewed[$k]=1; done
  for k in ${u//,/ }; do urgent[$k]=1; done
  for k in ${f//,/ }; do focused[$k]=1; done
  for k in ${o//,/ }; do occupied[${k%%:*}]=1; done
  local out=() label
  for k in $(printf '%s\n' "${!viewed[@]}" "${!occupied[@]}" | sort -n | uniq); do
    if (( k > 9 )); then label="F$((k - 9))"; else label=$k; fi
    [[ -n ${focused[$k]:-} ]] && label="$label*"
    [[ -n ${urgent[$k]:-} ]] && label="$label!"
    [[ -n ${viewed[$k]:-} ]] && label="[$label]"
    out+=("$label")
  done
  local text="${out[*]}"
  printf '{"text": "%s", "class": "tags", "tooltip": "view %s · occupied %s"}\n' "${text//\"/}" "$v" "${o//\"/}"
}

# initial state, then follow the socket
( sleep 0.3; /usr/bin/hyprctl eval 'hyprdwmland.emit()' >/dev/null 2>&1 ) &
/usr/bin/socat -u "UNIX-CONNECT:$SOCK" - | while IFS= read -r ev; do
  [[ $ev == "custom>>hyprdwmland>>$MON|"* ]] || continue
  [[ ${#ev} -le 4096 ]] || continue
  render "${ev#custom>>hyprdwmland>>}"
done
