#!/usr/bin/env bash
# Reverse install.sh. Removes only what install.sh wrote:
#   - the single marked block in ~/.config/hypr/hyprland.lua (refuses on malformed markers)
#   - this widget's entries in ~/.config/omarchy/shell.json (omarchy.workspaces put back)
# Then reloads Hyprland and restarts the shell.
#
#   uninstall.sh                 windows go to the workspace numbered like their tag
#                                (lowest tag; tags above 10 go to 1), tags stripped, then
#                                the config edits are reversed
#   uninstall.sh --keep-windows  leave windows where they are (on 101/102, tags intact)
#   uninstall.sh --purge-state   also deletes ~/.local/state/hypr-dwm-land
# The plugin folder itself is removed with: omarchy plugin remove <id>
set -euo pipefail
umask 077

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JQ=/usr/bin/jq
HYPRCTL=/usr/bin/hyprctl
ID=$("$JQ" -r '.id' "$REPO/manifest.json")
[[ $ID =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "bad plugin id in manifest" >&2; exit 1; }
HYPR="$HOME/.config/hypr/hyprland.lua"
SHELLJSON="$HOME/.config/omarchy/shell.json"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-dwm-land"
BEGIN="-- BEGIN hypr-dwm-land (managed by $ID/install.sh; remove with uninstall.sh)"
END="-- END hypr-dwm-land"
stamp=$(date +%s)
reset_windows=1; purge=0
for a in "$@"; do
  case $a in
    --keep-windows) reset_windows=0 ;;
    --reset-windows) reset_windows=1 ;;   # the default; kept for scripts
    --purge-state) purge=1 ;;
    *) echo "usage: uninstall.sh [--keep-windows] [--purge-state]" >&2; exit 2 ;;
  esac
done

replace_file() {
  local dest=$1 tmp
  tmp=$(mktemp -p "$(dirname -- "$dest")" ".$(basename -- "$dest").XXXXXXXXXX")
  cat >"$tmp"
  mv -f -T -- "$tmp" "$dest"
}

if (( reset_windows )); then
  "$HYPRCTL" eval 'hyprdwmland.uninstall()' >/dev/null 2>&1 || true
fi

# 1. hyprland.lua: exactly one BEGIN and one END, BEGIN before END, else refuse.
if [[ -f $HYPR ]]; then
  nb=$(grep -cF -- "$BEGIN" "$HYPR" || true)
  ne=$(grep -cF -- "$END" "$HYPR" || true)
  if (( nb == 0 && ne == 0 )); then
    echo "no hypr-dwm-land block in hyprland.lua" >&2
  elif (( nb != 1 || ne != 1 )); then
    echo "refusing: hyprland.lua has $nb BEGIN and $ne END markers; fix by hand" >&2
    exit 1
  else
    cp -- "$HYPR" "$HYPR.bak.$stamp"
    /usr/bin/awk -v b="$BEGIN" -v e="$END" '
      $0 == b { skip = 1; next }
      $0 == e { if (!skip) { print "END before BEGIN" > "/dev/stderr"; exit 1 }; skip = 0; next }
      !skip { print }
      END { if (skip) { print "unterminated block" > "/dev/stderr"; exit 1 } }' "$HYPR" | replace_file "$HYPR"
    # drop the single blank line install.sh added before the block, if it is the last line
    /usr/bin/sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR"
  fi
fi

# 2. shell.json: put omarchy.workspaces back where this widget sits; drop the plugin entry.
if [[ -f $SHELLJSON ]] && grep -q "\"$ID\"" "$SHELLJSON"; then
  cp -- "$SHELLJSON" "$SHELLJSON.bak.$stamp"
  "$JQ" --arg id "$ID" '(.bar.layout |= with_entries(.value |= map(if .id==$id then {id:"omarchy.workspaces"} else . end)))
      | (.plugins |= ((. // []) | map(select(.id != $id))))' \
    "$SHELLJSON" | replace_file "$SHELLJSON"
fi

if (( purge )) && [[ -d $STATE && ! -L $STATE && -O $STATE ]]; then
  rm -f -- "$STATE/state" "$STATE/debug.txt" "$STATE"/.state.*.tmp
  rmdir -- "$STATE" 2>/dev/null || true
fi

"$HYPRCTL" reload >/dev/null || true
omarchy restart shell >/dev/null 2>&1 || true
echo "hypr-dwm-land config removed. Remaining: the plugin folder (omarchy plugin remove $ID)$( (( purge )) || printf ', %s' "$STATE")."
