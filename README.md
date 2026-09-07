# Hyprtags

DWM-style tags for Hyprland on Omarchy, written entirely in Hyprland's Lua config
(`require`-able module, no compiled plugin) plus a Quickshell bar widget for the Omarchy shell.

Tested on Omarchy 4.0.2, Hyprland 0.56.2 (Lua 5.5), Quickshell 0.3.1.

## How it works

- **Workspace pairs.** Each monitor gets two real workspaces: a *visible* one (the only one
  ever focused) and a *hidden* parking lot. eDP-1 uses 101/102, the next monitor 201/202, and
  so on; the slot is remembered per monitor name in `~/.local/state/hyprtags/state.lua`.
  Workspaces 1..99 stay free for Omarchy window rules; `special:scratchpad` is untouched.
- **Membership in Hyprland's own window tags.** A window on tags 3 and 5 carries `WMT3` and
  `WMT5`. These are exact names, so Hyprland window rules and `hl.get_windows({ tag = "WMT3" })`
  match them (Hyprland's tag matching is exact `std::set` lookup, no prefix or regex).
- **Stack position in one more tag**, `WMT_POS{3:1,5:2}` = rank 1 in tag 3, rank 2 in tag 5.
  Ranks are snapshotted from on-screen geometry when a window is *hidden*, for the tags that
  were in the view being left. Re-viewing a tag re-inserts its windows lowest rank first, so
  a stack comes back arranged as you left it. Tags not in the view are never touched, so what
  you do on tag 3 cannot rearrange tag 5.
- **The view** is a set of tags per monitor. `reconcile()` moves windows between the pair
  with `hl.dsp.window.move({ follow = false, window = … })` so nothing else changes.
- **New windows** take the current view's tags. A window that an Omarchy rule sends to
  workspace *N* (e.g. `o.window("qemu", { workspace = "5" })`) is adopted as tag *N*.
- **Nothing stays untagged.** Any mapped window outside the scratchpad that carries no tag is
  given tag 1 (`stray_tag`) and moved into the pair, checked after every change and on a 2 s
  sweep, so a window can never sit on a workspace the keys cannot reach.
- **Focus comes back where you left it.** The focused window is remembered per view (per
  monitor) and refocused when that view returns, dwm/pertag style.
- **Self-protecting.** Every keybind is registered per chord, so one failing bind cannot take
  the keyboard with it; failures are listed by `debug()`. A pair workspace dragged to another
  monitor is sent home once per second, and the feature disables itself if the move does not
  take (untested on real hardware, see below). Error toasts are rate-limited.
- **The bar** gets one socket2 line per monitor on every change
  (`custom>>hyprtags>>eDP-1|v=2,3|o=1:2,2:1|u=|f=2`: viewed, occupied with counts, urgent,
  focused-window tags) and talks back with `hyprctl eval 'hyprtags.view(3, "eDP-1")'`.

Everything the compositor needs survives a config reload (tags and placement are compositor
state); the module rebuilds its view from the state file and checks it against where windows
actually sit.

## Install

```sh
git clone <this repo> ~/Hyprtags-lua
~/Hyprtags-lua/install.sh
```

The script copies the widget into `~/.config/omarchy/plugins/person1873.hyprtags/` (Omarchy
refuses symlinked plugin folders), swaps `omarchy.workspaces` for it in
`~/.config/omarchy/shell.json`, appends the loader to `~/.config/hypr/hyprland.lua`, reloads
Hyprland and restarts the shell. Every config edit is backed up as `*.bak.<timestamp>` and made
only once; re-run the script after editing the widget.

The loader line is:

```lua
package.path = os.getenv("HOME") .. "/Hyprtags-lua/?.lua;" .. os.getenv("HOME") .. "/Hyprtags-lua/?/init.lua;" .. package.path
require("hyprtags").setup({})
```

It must run after Omarchy's defaults and your own `hypr/bindings.lua`, because the keys
module unbinds the Omarchy chords it replaces and every bind on a key fires.

`setup()` options: `keys` (Lua module name that binds the keys; default `"hyprtags.keys"`,
`false` = bind nothing), `ntags` (default 21), `stray_tag` (default 1), `stray_sweep` ms
(default 2000, 0 = only on changes), `combo_timeout` ms, `emit_delay` ms.

## Keys

The engine binds nothing itself. A **keys module** does, using the public `hyprtags.*`
functions plus `hyprtags.rebind(keys, fn, desc)` (unbind the chord, bind ours, report
failures) and `hyprtags.unbind(keys)`. Two maps ship:

**`hyprtags/keys.lua` (default)** keeps Omarchy's own chords and points them at tags:

| keys | action | Omarchy meaning |
|---|---|---|
| `SUPER + 1..9, 0` | view tag 1..10 | switch workspace |
| `SUPER + SHIFT + n` | tag n and follow | move window to workspace |
| `SUPER + SHIFT + ALT + n` | tag n, stay | move silently |
| `SUPER + CTRL + n` | toggle tag n in the view | (free) |
| `SUPER + CTRL + SHIFT + n` | toggle tag n on the window | (free) |
| `SUPER + TAB` / `SHIFT + TAB` | next / previous occupied tag | next / previous workspace |
| `SUPER + CTRL + TAB` | previous view | former workspace |
| `SUPER + mouse wheel` | next / previous occupied tag | scroll workspaces |

**`examples/keys-dwm.lua`** is the dwm-flexipatch map. Copy it to
`~/.config/hypr/hyprtags-keys.lua`, edit freely, and load it with
`require("hyprtags").setup({ keys = "hypr.hyprtags-keys" })`:

| keys | action |
|---|---|
| `SUPER + 1..9`, `SUPER + F1..F12` | view tag 1..9 / 10..21 (hold SUPER and press several to view them together) |
| `SUPER + SHIFT + <tag key>` | put the focused window on that tag only (combo: several tags) |
| `SUPER + CTRL + <tag key>` | toggle the tag in the view |
| `SUPER + CTRL + SHIFT + <tag key>` | toggle the tag on the focused window |
| `SUPER + 0` / `SUPER + SHIFT + 0` | view all (again: back to the previous view) / tag with all |
| `SUPER + TAB` | previous view (back and forth) |
| `SUPER + U` | focus the urgent window (reveals its tag) |
| `SUPER + O` | view the focused window's tags (Pop window out moves to `SUPER + ALT + O`) |
| `SUPER + SHIFT + S` | sticky (pin) |
| `SUPER + CTRL + LEFT/RIGHT` | shift window and view to the previous/next tag |
| `SUPER + SHIFT + , / .` | send window to the previous/next monitor (takes that monitor's view) |

Public functions for your own map: `view(tags, mon?)`, `toggleview(k)`, `tag(tags, w?)`,
`toggletag(k, w?)`, `view_all()`, `tag_all()`, `view_previous()`, `view_next(±1)`,
`comboview(k)`, `combotag(k)`, `combo_enable("SUPER")`, `focusurgent()`, `winview()`,
`sticky()`, `shiftboth(±1)`, `shiftview(±1)`, `tagmon(±1)`.

Bar widget: left click = view, right click = toggle into view, **Ctrl** + left = tag the
focused window, **Ctrl** + right = toggle the tag on it. (SUPER + mouse is consumed by
Omarchy's global drag/resize binds and never reaches the bar.) Empty tags are hidden; viewed
tags always show; the tag holding the focused window shows a glyph; urgent tags use the bar's
urgent colour.

Scratchpad: Omarchy's `SUPER + ALT + S` sends the focused window to the scratchpad (it keeps
its tags) and `SUPER + S` shows or hides the scratchpad. To bring a window back, focus it in
the shown scratchpad and press any tag key (`SUPER + SHIFT + 3`, or `SUPER + CTRL + SHIFT + 3`
to keep its old tags too): it leaves the scratchpad and lands on screen if one of its tags is
viewed, otherwise parked on that tag.

Each keys file lists the Omarchy chords it displaces in its header comment.

### dwm app/window layer (in `~/.config/hypr/bindings.lua`, not in the module)

Apps go through Omarchy's default-app selectors, never a hard-coded binary:

| keys | action | displaced Omarchy chord |
|---|---|---|
| `SUPER + P` | apps menu (`omarchy-menu toggle apps`) | Pseudo window |
| `SUPER + R` | Omarchy menu | — |
| `SUPER + RETURN` | terminal (`xdg-terminal-exec`, Omarchy default) | — |
| `SUPER + W` | focus the running default browser (any tag) or launch it; class read from the xdg default browser's desktop entry | Close window → `SUPER + X` |
| `SUPER + ALT + W` | find window: `bin/hyprtags-windows`, every window with its tags in the Omarchy picker; focusing a hidden one reveals its tag | — |
| `SUPER + X` | close window | Universal cut |
| `SUPER + M` | mail (xdg `mailto` handler) | — |
| `SUPER + SHIFT + RETURN` | swap with master (dwm zoom) | duplicate Browser (`SUPER + SHIFT + B` stays) |
| `SUPER + SHIFT + I` / `D` | add / remove master | Docker TUI |
| `SUPER + SHIFT + R` | reload Hyprland config | — |

## Using it from scripts

Everything is on the global `hyprtags` table inside Hyprland's Lua state:

```sh
hyprctl eval 'hyprtags.view(3)'              # optional second arg: monitor name
hyprctl eval 'hyprtags.toggleview(4)'
hyprctl eval 'hyprtags.tag({2, 5})'          # focused window; or pass an HL.Window second
hyprctl eval 'hyprtags.toggletag(2)'
hyprctl eval 'hyprtags.view_previous()'
hyprctl eval 'hyprtags.emit()'               # re-send the bar state
hyprctl eval 'hyprtags.relayout()'           # snapshot ranks now, without hiding
hyprctl eval 'hyprtags.debug()'              # writes ~/.local/state/hyprtags/debug.txt
hyprctl eval 'hyprtags.uninstall()'          # strip tags, everything back on workspace 1
```

`hyprctl eval` prints only `ok` or an error; read state with `hyprctl clients -j` (tags),
`hyprctl workspaces -j`, or the debug file.

## Verifying

```sh
hyprctl workspaces -j | jq '.[]|{id,name,monitor,windows}'      # 101/102 on eDP-1
hyprctl clients -j | jq '.[]|{class,ws:.workspace.id,tags}'      # WMT<n> + WMT_POS{..} per window
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | grep custom
hyprctl binds -j | jq -r '.[]|select(.description|test("tag";"i"))|.description' | sort | uniq -d   # empty
```

Exercised on 2026-09-08: adoption of new windows, rank snapshot and restoration after a swap,
bounce when the hidden workspace is focused, adoption from a numbered workspace, scratchpad
round trip keeping tags, view survives `hyprctl reload`, digit combos with modifier release.
Not yet exercised: a second monitor (pair 201/202, `tagmon`, Omarchy's
`SUPER + SHIFT + ALT + arrows` workspace move being bounced back).

## Uninstall

```sh
hyprctl eval 'hyprtags.uninstall()'
```
then remove the loader lines from `~/.config/hypr/hyprland.lua`, restore the `shell.json`
backup (or put `omarchy.workspaces` back), delete
`~/.config/omarchy/plugins/person1873.hyprtags`, and `omarchy restart shell`.

## Layout

```
bin/hyprtags-windows            lost-window finder on omarchy-menu-select (--list to print)
hyprtags/init.lua               the engine (no keybinds)
hyprtags/keys.lua               default keys: Omarchy's chords on tags
examples/keys-dwm.lua           dwm-flexipatch keys, for ~/.config/hypr/hyprtags-keys.lua
shell/person1873.hyprtags/        Omarchy shell bar-widget (manifest.json, Tags.qml)
install.sh                      idempotent installer
```
