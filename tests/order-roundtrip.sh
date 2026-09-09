#!/usr/bin/env bash
# Round-trip order test: N foot windows on tag T, hide (view 1), re-show, compare cells.
# Usage: tests/order-roundtrip.sh <tag> <count> <label>. Flips the view; run it on a machine
# you are not working at, or accept the flicker. Windows are closed afterwards.
set -u
T=$1; N=$2; LABEL=$3
ev() { hyprctl eval "$1" >/dev/null; }
cells() { hyprctl clients -j | jq -r --arg t "^ot[0-9]+$" '.[]|select(.workspace.id==101 and (.title|test($t)))|[.title,.at[0],.at[1]]|@tsv' | sort; }
for i in $(seq 1 $N); do ev "hl.exec_cmd(\"foot -T ot$i sleep 900\", { workspace = \"102\" })"; sleep 0.45; done; sleep 1.5
ev "for _, w in ipairs(hl.get_windows()) do if w.title and w.title:match('^ot%d+$') then hyprdwmland.tag({$T}, w) end end"; sleep 1
ev "hyprdwmland.view($T)"; sleep 2.5
before=$(cells)
fails=0
for r in 1 2; do
  ev 'hyprdwmland.view(1)'; sleep 1.5; ev "hyprdwmland.view($T)"; sleep 2.5
  after=$(cells)
  if [[ "$after" != "$before" ]]; then fails=$((fails+1)); echo "  round $r differs:"; diff <(echo "$before") <(echo "$after") | sed 's/^/    /'; fi
done
n_on=$(echo "$before" | wc -l)
echo "$LABEL N=$N: windows visible $n_on, rounds failed $fails"
ev 'hyprdwmland.view(1)'; sleep 1
for a in $(hyprctl clients -j | jq -r '.[]|select(.title|test("^ot[0-9]+$"))|.address'); do hyprctl dispatch "hl.dsp.window.close({ window = 'address:$a' })" >/dev/null; done; sleep 1.5
