#!/usr/bin/env bash
# Hyprtags installer for Omarchy. Run it yourself; nothing here runs on plugin load.
#
#   omarchy plugin add <git url> --enable
#   ~/.config/omarchy/plugins/person1873.hyprtags/install.sh
# or from a development checkout elsewhere (copies the tree into the plugin folder).
#
# What it edits, each behind a backup (*.bak.<timestamp>) and made once:
#   ~/.config/omarchy/shell.json   omarchy.workspaces -> this widget, plugin registered
#   ~/.config/hypr/hyprland.lua    one marked block appended (see uninstall.sh)
# Then `hyprctl reload`; if `hyprctl configerrors` reports anything the hyprland.lua
# edit is rolled back to the exact prior bytes.
set -euo pipefail
umask 077

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
JQ=/usr/bin/jq
HYPRCTL=/usr/bin/hyprctl
ID=$("$JQ" -r '.id' "$REPO/manifest.json")
[[ $ID =~ ^[a-z0-9][a-z0-9._-]*$ ]] || { echo "bad plugin id in manifest" >&2; exit 1; }
PLUG="$HOME/.config/omarchy/plugins/$ID"
HYPR="$HOME/.config/hypr/hyprland.lua"
SHELLJSON="$HOME/.config/omarchy/shell.json"
BEGIN="-- BEGIN hyprtags (managed by $ID/install.sh; remove with uninstall.sh)"
END="-- END hyprtags"
stamp=$(date +%s)

# Atomic replace: exclusive temporary in the destination directory, then rename.
replace_file() { # replace_file <dest> < new-content
  local dest=$1 tmp
  tmp=$(mktemp -p "$(dirname -- "$dest")" ".$(basename -- "$dest").XXXXXXXXXX")
  cat >"$tmp"
  mv -f -T -- "$tmp" "$dest"
}

# 1. Plugin folder. Omarchy refuses symlinked plugin folders, so a dev checkout is copied;
#    a checkout made by `omarchy plugin add` already is the plugin folder.
if [[ $REPO != "$PLUG" ]]; then
  mkdir -p -m 700 "$PLUG"
  [[ ! -L $PLUG && -d $PLUG && -O $PLUG ]] || { echo "refusing: $PLUG is not a directory owned by you" >&2; exit 1; }
  (cd "$REPO" && find . -path ./.git -prune -o -type f -print0 |
    while IFS= read -r -d '' f; do
      mkdir -p "$PLUG/$(dirname "$f")"
      replace_file "$PLUG/$f" <"$f"
      if [[ -x $f ]]; then chmod u+x "$PLUG/$f"; fi
    done)
fi
omarchy plugin validate "$PLUG"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# 2. shell.json: swap omarchy.workspaces for this widget and register the plugin.
if [[ -f $SHELLJSON ]] && ! grep -q "\"$ID\"" "$SHELLJSON"; then
  cp -- "$SHELLJSON" "$SHELLJSON.bak.$stamp"
  "$JQ" --arg id "$ID" '(.bar.layout |= with_entries(.value |= map(if .id=="omarchy.workspaces" then {id:$id} else . end)))
      | (.plugins |= ((. // []) | if any(.[]; .id==$id) then . else . + [{id:$id}] end))' \
    "$SHELLJSON" | replace_file "$SHELLJSON"
fi

# 3. hyprland.lua: one marked block, refused if a marker is already present.
if grep -qF -- "$BEGIN" "$HYPR" || grep -qF -- "$END" "$HYPR"; then
  echo "hyprland.lua already carries a hyprtags block; nothing appended" >&2
else
  cp -- "$HYPR" "$HYPR.bak.$stamp"
  {
    cat -- "$HYPR"
    printf '\n%s\n' "$BEGIN"
    printf 'package.path = "%s/?.lua;%s/?/init.lua;" .. package.path\n' "$PLUG" "$PLUG"
    printf 'require("hyprtags").setup({})\n'
    printf '%s\n' "$END"
  } | replace_file "$HYPR"
fi

# 4. Apply, with rollback of the hyprland.lua edit if the config no longer loads cleanly.
"$HYPRCTL" reload >/dev/null || true
errs=$("$HYPRCTL" configerrors || true)
if [[ -n $errs ]]; then
  echo "hyprctl configerrors after install:" >&2
  echo "$errs" >&2
  if [[ -f $HYPR.bak.$stamp ]]; then
    replace_file "$HYPR" <"$HYPR.bak.$stamp"
    "$HYPRCTL" reload >/dev/null || true
    echo "hyprland.lua restored from $HYPR.bak.$stamp" >&2
  fi
  exit 1
fi
omarchy restart shell >/dev/null 2>&1 || true
echo "hyprtags installed as $ID. Try SUPER+1..9; README.md has the key maps and uninstall.sh reverses this."
