#!/usr/bin/env bash
# Idempotent installer for Hyprtags on Omarchy.
#
# Two ways in:
#   omarchy plugin add <git url> --enable      # clones this repo as the plugin, then run
#   ~/.config/omarchy/plugins/person1873.hyprtags/install.sh
# or, from a development checkout anywhere:
#   ~/Hyprtags-lua/install.sh                  # copies the tree into the plugin folder
#
# Safe to re-run: config edits are made once and backed up as *.bak.<timestamp>.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ID=$(jq -r '.id' "$REPO/manifest.json")
PLUG="$HOME/.config/omarchy/plugins/$ID"
HYPR="$HOME/.config/hypr/hyprland.lua"
SHELLJSON="$HOME/.config/omarchy/shell.json"
stamp=$(date +%s)

# 1. Plugin folder. Omarchy refuses symlinked plugin folders, so a dev checkout is copied;
#    a checkout made by `omarchy plugin add` already is the plugin folder.
if [[ $REPO != "$PLUG" ]]; then
  mkdir -p "$PLUG"
  (cd "$REPO" && find . -path ./.git -prune -o -type f -print0 |
    while IFS= read -r -d '' f; do mkdir -p "$PLUG/$(dirname "$f")"; cp -f "$f" "$PLUG/$f"; done)
fi
omarchy plugin validate "$PLUG"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# 2. shell.json: replace omarchy.workspaces with the tags widget, register the plugin.
if [[ -f $SHELLJSON ]] && ! grep -q "\"$ID\"" "$SHELLJSON"; then
  cp "$SHELLJSON" "$SHELLJSON.bak.$stamp"
  tmp=$(mktemp)
  jq --arg id "$ID" '(.bar.layout |= with_entries(.value |= map(if .id=="omarchy.workspaces" then {id:$id} else . end)))
      | (.plugins |= ((. // []) | if any(.[]; .id==$id) then . else . + [{id:$id}] end))' \
    "$SHELLJSON" >"$tmp" && mv "$tmp" "$SHELLJSON"
fi

# 3. hyprland.lua: load the module from the plugin folder, after Omarchy's defaults and the
#    personal bindings so the keys module's unbinds win.
if ! grep -q 'require("hyprtags")' "$HYPR"; then
  cp "$HYPR" "$HYPR.bak.$stamp"
  cat >>"$HYPR" <<EOF

-- Hyprtags: DWM-style tags (see $PLUG/README.md). Must come after the Omarchy
-- defaults and the personal bindings so its unbinds win.
package.path = "$PLUG/?.lua;$PLUG/?/init.lua;" .. package.path
require("hyprtags").setup({})
EOF
fi

# 4. Apply.
hyprctl reload >/dev/null
errs=$(hyprctl configerrors)
[[ -z $errs ]] || { echo "hyprctl configerrors:"; echo "$errs"; exit 1; }
omarchy restart shell >/dev/null 2>&1 || true
echo "hyprtags installed as $ID. Try SUPER+1..9; see README.md for the key maps."
