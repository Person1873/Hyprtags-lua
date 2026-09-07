# hypr-dwm-land

Tags instead of workspaces for Hyprland, the way dwm does it. A Lua module for Hyprland's
Lua config, plus a bar widget for the Omarchy shell. No compiled code. The module itself
needs only Hyprland; see [Without Omarchy](#without-omarchy).

![the bar widget showing tags 1, 2 and 4](preview.png)

Tested on Omarchy 4.0.2, Hyprland 0.56.2 (Lua 5.5), Quickshell 0.3.1. Built with an AI
assistant; [AUTHORSHIP.md](AUTHORSHIP.md) says which decisions were human, which code was
generated, and what has and has not been tested.

## What tags are, in one minute

With workspaces, every window lives on exactly one workspace and you look at one workspace
at a time.

With tags, every window carries a **set** of tags (think labels: 1, 2, 3 …) and what you look
at is also a set, called the **view**. A window is on screen when its tags and the view
overlap. So:

- Put a browser on tag 2 and a terminal on tag 3, then view tag 2: you see the browser.
- View tags 2 and 3 together: you see both, side by side in the layout.
- Give one window tags 1 *and* 3: it appears whenever you view 1 or 3.
- Press "view all": everything is on screen.

Empty tags do not exist as places; a tag is just a label some windows carry. The bar shows
only the tags that have windows, plus whatever you are viewing.

## Quick start

Three Omarchy commands put the widget where the workspace numbers were:

```sh
omarchy plugin add https://github.com/Person1873/hypr-dwm-land.git --enable
omarchy bar put person1873.hypr-dwm-land --after omarchy.menu
omarchy plugin disable omarchy.workspaces
```

Then three lines at the end of `~/.config/hypr/hyprland.lua`, after your own keybindings,
so the keys module's unbinds win:

```lua
local hdl = os.getenv("HOME") .. "/.config/omarchy/plugins/person1873.hypr-dwm-land"
package.path = hdl .. "/?.lua;" .. hdl .. "/?/init.lua;" .. package.path
require("hyprdwmland").setup({})
```

`hyprctl reload`, then `hyprctl configerrors` should print nothing. Nothing edits your
config for you and nothing runs on plugin load.

Then, with the default key map (Omarchy's own chords; the dwm map below differs, notably
`SUPER + TAB`):

| press | to |
|---|---|
| `SUPER + 2` | view tag 2 |
| `SUPER + SHIFT + 3` | put the focused window on tag 3 and go there |
| `SUPER + CTRL + 3` | add tag 3 to what you are viewing |
| `SUPER + CTRL + SHIFT + 3` | also give the focused window tag 3 |
| `SUPER + TAB` | next tag that has windows |

The full maps are under [Keys](#keys); what the module writes at run time is under
[What it touches](#what-it-touches); [Removing](#removing) undoes everything.

## How it works

Hyprland has no tags, so the module builds them from things Hyprland does have.

**Two workspaces per monitor.** One is *visible* and is the only workspace ever focused.
The other is a *parking lot* for windows that are not in the current view. Switching the
view means moving windows between the two, silently, so nothing else changes. The visible
workspace is 101 on the first monitor, 201 on the second, and so on; the parking lots are
102, 202 … Ordinary workspaces 1..99 are left alone. The parking lot runs the monocle
layout, so a parked window is sized to the full monitor rather than to an ever-smaller
tile. Floating windows are never laid out and keep their exact position and size through
any number of view changes.

**Tags are Hyprland window tags.** Hyprland lets any window carry named tags. A window on
tags 3 and 5 carries `WMT3` and `WMT5`. Because these are plain names, Hyprland's own window
rules can match them (`match = { tag = "WMT9" }`), and so can `hl.get_windows({ tag = … })`.

**Position is remembered too.** When windows leave the screen Hyprland forgets where they
sat in the layout. So each window also carries `WMT_POS{3:1,5:2}`: rank 1 among tag 3's
windows, rank 2 among tag 5's. Ranks are taken from on-screen geometry at the moment a window
is hidden, only for the tags being left. When a tag comes back its windows are re-inserted
lowest rank first, so the stack comes back as you left it. Rearranging tag 3 never touches
tag 5's ranks.

**Layouts follow tags.** Each tag remembers its layout (dwindle, master, centre master,
monocle, scrolling) and it is applied when that tag is viewed. A view of several tags uses
the lowest tag's layout; the all-tags view has its own.

**Focus follows tags.** The focused window is remembered per view and refocused when the
view returns.

**Where a new window lands.** Without a rule, on the tags you are viewing when it opens. If
an Omarchy window rule assigns it a workspace, say `o.window("qemu", { workspace = "5" })`,
it goes on tag 5 instead: on screen if 5 is in view, otherwise parked.

**Nothing stays untagged.** Any window outside the scratchpad with no tag is given tag 1
and moved into the pair, on every change and on a 2 s sweep, so a window can never sit on a
workspace the keys cannot reach.

**Tabbed groups are one unit.** Hyprland moves a whole group when any member moves, so a
group has one membership: tagging any member tags them all, and a group formed by hand from
windows on different tags takes the union of their tags. A tag command on a grouped window
therefore never splits the group.

**The scratchpad is untouched.** Omarchy's `special:scratchpad` keeps working exactly as
shipped (`SUPER + S` show/hide, `SUPER + ALT + S` send). Windows there keep their tags but are
not counted on the bar. To bring one back, focus it in the shown scratchpad and press any
tag key: it lands on screen if that tag is viewed, otherwise parked on that tag.

**The bar** gets one line per monitor over Hyprland's event socket whenever anything
changes, and talks back with `hyprctl eval`. Left click views a tag, right click adds it to
the view, **Ctrl** + left puts the focused window on it, **Ctrl** + right toggles the window's
membership. (SUPER + mouse never reaches the bar; Omarchy binds it globally for drag and
resize.) The tag holding the focused window shows a glyph; urgent tags use the bar's urgent
colour.

Everything a Hyprland config reload would forget is either compositor state (tags, window
placement) or in a small state file the module re-reads and checks against reality.

## Keys

The module binds nothing by itself. A **keys module**, a Lua file, does the binding, using
the module's public functions. Two maps ship. Change the map with
`require("hyprdwmland").setup({ keys = "<module name>" })`; `keys = false` binds nothing.

### Default map (`hyprdwmland/keys.lua`): Omarchy's chords, pointed at tags

*n* is a digit `1`..`9`; `0` is tag 10.

| keys | action | what Omarchy used it for |
|---|---|---|
| `SUPER +` *n* | view tag *n* | switch workspace |
| `SUPER + SHIFT +` *n* | tag *n* and follow | move window to workspace |
| `SUPER + SHIFT + ALT +` *n* | tag *n*, stay | move silently |
| `SUPER + CTRL +` *n* | toggle tag *n* in the view | (free) |
| `SUPER + CTRL + SHIFT +` *n* | toggle tag *n* on the window | (free) |
| `SUPER + TAB` / `SHIFT + TAB` | next / previous tag with windows | next / previous workspace |
| `SUPER + CTRL + TAB` | previous view | former workspace |
| `SUPER + mouse wheel` | next / previous tag with windows | scroll workspaces |

### dwm map (`examples/keys-dwm.lua`)

This is the author's own map, carried over from a personal dwm-flexipatch build. It is not
what dwm or flexipatch ship, and some of it is muscle memory rather than good design. Copy it
to `~/.config/hypr/hypr-dwm-land-keys.lua`, edit freely, and load it with
`require("hyprdwmland").setup({ keys = "hypr.hypr-dwm-land-keys" })`.

*n* is a digit `1`..`9` for tags 1..9, or `F1`..`F12` for tags 10..21.

| keys | action |
|---|---|
| `SUPER +` *n* | view tag *n* (hold SUPER and press several to view them together) |
| `SUPER + SHIFT +` *n* | put the focused window on tag *n* only (combo: several tags) |
| `SUPER + CTRL +` *n* | toggle tag *n* in the view |
| `SUPER + CTRL + SHIFT +` *n* | toggle tag *n* on the focused window |
| `SUPER + 0` / `SUPER + SHIFT + 0` | view all (again: back to the previous view) / tag with all |
| `SUPER + TAB` | previous view (back and forth) |
| `SUPER + U` | focus the urgent window (reveals its tag) |
| `SUPER + O` | view the focused window's tags (Omarchy's "pop window out" moves to `SUPER + ALT + O`) |
| `SUPER + SHIFT + S` | sticky (pin) |
| `SUPER + CTRL + LEFT/RIGHT` | shift window and view to the previous/next tag |
| `SUPER + SHIFT + , / .` | send window to the previous/next monitor (takes that monitor's view) |
| `SUPER + SHIFT + T / M / C` | this tag's layout: master (dwm tile) / monocle / scrolling (dwm columns) |
| `SUPER + SHIFT + SPACE` | this tag's previous layout |
| `SUPER + CTRL + T`, `SUPER + CTRL + RETURN` | rotate the master orientation / mirror master and stack |
| `SUPER + CTRL + J / K` | roll the master stack forward / backward |
| `SUPER + ALT + 0` | toggle gaps |

Each keys file lists the Omarchy chords it displaces in its header comment.

### Writing your own map

Public functions on the global `hyprdwmland` table: `view(tags, mon?)`, `toggleview(k)`,
`tag(tags, w?)`, `toggletag(k, w?)`, `view_all()`, `tag_all()`, `view_previous()`,
`view_next(±1)`, `comboview(k)`, `combotag(k)`, `combo_enable("SUPER")`, `focusurgent()`,
`winview()`, `sticky()`, `shiftboth(±1)`, `shiftview(±1)`, `tagmon(±1)`, `cycle_layout(±1)`,
`set_layout(name, opts)`, `toggle_layout()`, `rotate_layout_axis(±1)`, `mirror_layout()`,
`toggle_gaps()`, `emit()`, `relayout()`, `debug()`, `uninstall()`.

Binding helpers: `hyprdwmland.rebind(keys, fn, description)` unbinds whatever is on the chord
and binds yours (every bind on a key fires, so this order matters); `hyprdwmland.bind` and
`hyprdwmland.unbind` are the halves. A bind that fails is logged and reported once; it never
takes the rest of the keyboard down.

## Using it from scripts

Everything is on the global `hyprdwmland` table inside Hyprland's Lua state:

```sh
hyprctl eval 'hyprdwmland.view(3)'              # optional second argument: monitor name
hyprctl eval 'hyprdwmland.toggleview(4)'
hyprctl eval 'hyprdwmland.tag({2, 5})'          # focused window
hyprctl eval 'hyprdwmland.emit()'               # re-send the bar state
hyprctl eval 'hyprdwmland.debug()'              # writes ~/.local/state/hypr-dwm-land/debug.txt
```

`hyprctl eval` prints only `ok` or an error. Read state with `hyprctl clients -j` (the
tags), `hyprctl workspaces -j`, or the debug file.

`bin/hypr-dwm-land-windows` is a lost-window finder: every window as `[tags] class · title` in
the Omarchy picker; picking one focuses it, which reveals its tag. `--list` prints the lines
instead. The dwm map's author binds it to `SUPER + ALT + W` in their own config.

## Without Omarchy

The engine is plain Hyprland Lua and has no Omarchy dependency: it reads and writes
Hyprland window tags, moves windows with `hl.dsp.window.move`, listens with `hl.on`, and
uses Hyprland's own notification overlay. Omarchy provides the bar widget, the installer and
the window finder's picker; a per-workspace layout file it happens to ship is read if
present and ignored if not.

Install by hand on any Hyprland with a Lua config (0.56 or later):

```sh
cp -r hyprdwmland ~/.config/hypr/          # the module directory
```

and at the end of `~/.config/hypr/hyprland.lua`, after your own keybindings:

```lua
require("hyprdwmland").setup({})           -- or { keys = "hypr.hypr-dwm-land-keys" } for a copy of examples/keys-dwm.lua
```

Hyprland's Lua loader searches `<config dir>/?.lua` and `<config dir>/?/init.lua`, so no
`package.path` line is needed. The default keys module unbinds Omarchy's chords before
binding; on a non-Omarchy config those unbinds are no-ops, and it then binds the standard
`SUPER + n` family. Reload with `hyprctl reload`, check `hyprctl configerrors`.

**Any bar can show tags.** The engine publishes one line per monitor on Hyprland's event
socket (`.socket2.sock`) whenever anything changes, as a `custom` event:

```
custom>>hyprdwmland>>eDP-1|v=2,3|o=1:2,2:1,5:1|u=5|f=2
```

| field | meaning |
|---|---|
| first field | monitor name |
| `v=` | tags in the view, comma-separated |
| `o=` | occupied tags as `tag:count` (a window on two tags counts on both) |
| `u=` | tags with an urgent window |
| `f=` | tags of the focused window, empty if focus is elsewhere |

Ask for a fresh line with `hyprctl eval 'hyprdwmland.emit()'`; act on clicks with
`hyprctl eval 'hyprdwmland.view(3, "eDP-1")'`, `toggleview`, `tag`, `toggletag` and the rest
of the functions under [Writing your own map](#writing-your-own-map).
[`examples/waybar-tags.sh`](examples/waybar-tags.sh) turns the stream into waybar
`custom` module JSON in about forty lines; its parsing is exercised, waybar itself was not
run here. The Omarchy widget in `shell/Tags.qml` is the reference consumer.

## Options

`require("hyprdwmland").setup({ ... })` accepts:

| option | default | meaning |
|---|---|---|
| `keys` | `"hyprdwmland.keys"` | keys module to load; `false` for none |
| `ntags` | `21` | how many tags exist (9 digits + 12 F-keys) |
| `stray_tag` | `1` | where an untagged window is put |
| `stray_sweep` | `2000` | ms between sweeps for untagged windows; `0` = only on changes |
| `layouts` | dwindle, master, centre master, monocle, scrolling | what `cycle_layout` walks |
| `warp_cursor` | `false` | let Hyprland warp the mouse to windows the engine focuses on a view change |
| `combo_timeout` | `1000` | ms fallback for ending a held-modifier combo |
| `emit_delay` | `30` | ms debounce for bar updates |

## What it touches

Nothing runs on plugin load, and the module edits no configuration: the `hyprland.lua`
lines are yours, and the bar layout is changed by Omarchy's own commands in the quick
start.

At run time it writes only under `~/.local/state/hypr-dwm-land/`: `state`, a passive
line-format file (per-monitor workspace slot, current and previous view, focused window per
view, layout per tag) that is parsed with anchored patterns and never executed; and
`debug.txt` on request. No network access, no daemons, no other files.
No sudo or pkexec is required.

Window tags themselves live in the compositor and vanish when Hyprland exits.

## Removing

```sh
hyprctl eval 'hyprdwmland.uninstall()'          # windows to workspaces numbered by tag
# delete the three hyprdwmland lines from ~/.config/hypr/hyprland.lua, then:
hyprctl reload
omarchy plugin disable person1873.hypr-dwm-land
omarchy plugin enable omarchy.workspaces --section left
omarchy plugin remove person1873.hypr-dwm-land
```

`hyprdwmland.uninstall()` hands windows back as if tags had been workspaces all along:
each goes to the workspace numbered like its lowest tag (tags above 10 go to workspace 1,
since Omarchy's keys stop there), its tags are stripped, and the workspace matching your
current view is focused. Scratchpad windows stay in the scratchpad. Skip that line to leave
windows on 101/102 with their tags instead.

What survives: `~/.local/state/hypr-dwm-land/`, which you may delete. Nothing else.

## Verifying an install

```sh
hyprctl workspaces -j | jq '.[]|{id,name,monitor,windows}'      # 101/102 on your monitor
hyprctl clients -j | jq '.[]|{class,ws:.workspace.id,tags}'      # WMT<n> + WMT_POS{..} per window
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | grep custom
```

What has been exercised, and what has not, is listed in [AUTHORSHIP.md](AUTHORSHIP.md).
Multi-monitor behaviour was tested on a headless output (`hyprctl output create headless`),
not on physical hardware.

## FAQ: tags are not workspaces

The plugin keeps Hyprland's own machinery working where it can, but tags are a different
model from workspaces, and anything that treats the two visible workspaces as the whole
story, or manages window tags for its own purposes, may not behave as it expects. Best
effort, not a guarantee. Known cases:

**Another tool shows workspaces 101 and 102 (or 201, 202), not tags.** That is what exists
at the Hyprland level; only this plugin's bar widget speaks tags. Clicking the parking
workspace in such a tool focuses it for an instant and is bounced back to the visible one.
Omarchy's stock `omarchy.workspaces` widget, if re-enabled beside this one, shows nothing
occupied because it only lists workspaces 1..10.

**A plugin or script cleared a window's tags and it jumped to tag 1.** Tag membership lives
in Hyprland's window tags (`WMT<n>`). Anything that runs `clearwindowtags` or
`hl.dsp.window.clear_tags` strips them, and the next sweep re-adopts the window to tag 1
(`stray_tag`) because an untagged window has nowhere else to go. Tools that add or remove
their own tags without clearing are unaffected.

**A window rule keyed on a `WMT` tag must not set `workspace`.** `match = { tag = "WMT3" }`
with `float`, `opacity`, `size` and the like works and is the point of the plain tag names.
With `workspace = "5"` the rule and the plugin fight over where the window lives: the rule
fires every time the tag is written, moves the window to 5, and the plugin adopts it back
as tag 5.

**Workspace-swipe gestures land in the parking lot.** Omarchy ships none. If you enable
Hyprland's `workspace` swipe gesture you will swipe into the parking workspace and be
bounced every time; bind the gesture to `hyprdwmland.view_next(±1)` instead.

**A script moved a window to a numbered workspace.** That is adopted as "put it on that
tag" (on screen if the tag is in view, parked otherwise), which is usually what was meant.
Tools that rearrange many windows this way have not been tested.

**Tabbed groups move together.** Hyprland moves a whole group when one member moves, so a
group has one membership; tagging any member tags them all. See "How it works".

**A tiled application breaks when it is resized.** A tiled window is resized twice per
round trip: to the full monitor when parked, to its tile when it returns. If an app cannot
survive that, give it an Omarchy float rule (`o.window("<class>", { float = true })`); a
floating window is never laid out, parked or not. Parking every window as floating was
considered and rejected: it would still resize them, only to less predictable sizes, and a
reload mid round-trip would leave windows floating.

**Second monitor.** Tested on a headless output only: the pair 201/202, windows opening
there, `tagmon` both ways, a silent cross-monitor move taking the destination's view,
Omarchy's "move workspace to monitor" being sent back, and removal landing the orphaned
windows in the survivor's parking lot with their tags. Physical hot-plug, differing scales
and DPMS have not been exercised. Report what you find.

## Prior art and credit

The model is [dwm](https://dwm.suckless.org/) by the suckless team: tags as a set per
window, `view` / `toggleview` / `tag` / `toggletag`, the back-and-forth on `view(0)`, `zoom`.
Several behaviours here mirror dwm patches: pertag (per-tag layout), combo (hold the
modifier, press several tags), hidevacanttags, winview, shiftboth, focusurgent, and
sendmon/tagmon. The author's key map comes from a
[dwm-flexipatch](https://github.com/bakkeby/dwm-flexipatch) build. The code was written by an
AI assistant that has dwm's source and its patches in its training data and drew on that
memory for behaviour (for example pertag's rule that a combined view uses its lowest tag's
slot). No dwm or flexipatch source is reproduced or structurally translated here: the data
model is Hyprland's (window tags, windows moved between two workspaces) rather than dwm's
client list and bitmasks, and the parts dwm never needed are the bulk of the code. Readers
are welcome to compare. dwm is MIT/X Consortium licensed.

[JoaoCostaIFG/hyprtags](https://github.com/JoaoCostaIFG/hyprtags) is an earlier, unrelated
C++ Hyprland plugin with the same aim, loaded through `hyprpm`. This project started life
under the name Hyprtags and was renamed to avoid being mistaken for it; no code is shared.

Built on [Hyprland](https://hyprland.org/) 0.56's Lua config and the
[Omarchy](https://omarchy.org/) shell plugin system.

## Layout of this repo

```
manifest.json               Omarchy plugin manifest (id person1873.hypr-dwm-land, bar-widget)
shell/Tags.qml              the bar widget
hyprdwmland/init.lua        the engine (no keybinds)
hyprdwmland/keys.lua        default keys: Omarchy's chords on tags
examples/keys-dwm.lua       the author's dwm-style keys, for ~/.config/hypr/hypr-dwm-land-keys.lua
examples/waybar-tags.sh     the bar protocol turned into waybar custom-module JSON
bin/hypr-dwm-land-windows   lost-window finder on omarchy-menu-select (--list to print)
```
