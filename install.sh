#!/usr/bin/env bash
# Idempotent installer for Hyprtags on Omarchy (Hyprland Lua config + Quickshell shell).
# Safe to re-run after editing the repo: copies the widget, keeps config edits once.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUG="$HOME/.config/omarchy/plugins/person1873.hyprtags"
HYPR="$HOME/.config/hypr/hyprland.lua"
SHELLJSON="$HOME/.config/omarchy/shell.json"
stamp=$(date +%s)

# 1. Bar widget. Omarchy refuses symlinked plugin folders, so the files are copied.
mkdir -p "$PLUG"
cp -f "$REPO"/shell/person1873.hyprtags/* "$PLUG"/
omarchy plugin validate "$PLUG"
omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true

# 2. shell.json: replace omarchy.workspaces with the tags widget, register the plugin.
if [[ -f $SHELLJSON ]] && ! grep -q '"person1873.hyprtags"' "$SHELLJSON"; then
  cp "$SHELLJSON" "$SHELLJSON.bak.$stamp"
  tmp=$(mktemp)
  jq '(.bar.layout |= with_entries(.value |= map(if .id=="omarchy.workspaces" then {id:"person1873.hyprtags"} else . end)))
      | (.plugins |= ((. // []) | if any(.[]; .id=="person1873.hyprtags") then . else . + [{id:"person1873.hyprtags"}] end))' \
    "$SHELLJSON" >"$tmp" && mv "$tmp" "$SHELLJSON"
fi

# 3. hyprland.lua: load the module after Omarchy's defaults and the personal bindings.
if ! grep -q 'require("hyprtags")' "$HYPR"; then
  cp "$HYPR" "$HYPR.bak.$stamp"
  cat >>"$HYPR" <<EOF

-- Hyprtags: DWM-style tags (see $REPO/README.md). Must come after the Omarchy
-- defaults and the personal bindings so its unbinds win.
package.path = "$REPO/?.lua;$REPO/?/init.lua;" .. package.path
require("hyprtags").setup({})
EOF
fi

# 4. Apply.
hyprctl reload >/dev/null
errs=$(hyprctl configerrors)
[[ -z $errs ]] || { echo "hyprctl configerrors:"; echo "$errs"; exit 1; }
omarchy restart shell >/dev/null 2>&1 || true
echo "hyprtags installed. Try SUPER+1..9; see README.md for the key map."
