---
name: hypr-dwm-land
description: "Drive hypr-dwm-land, dwm-style tags for Hyprland on Omarchy: view or compose tags, tag and move windows, read tag state, set per-tag layouts, name tags. Use whenever a task touches tags, views, workspaces or window placement on a machine running it. Every view change is visible to the user."
---

# hypr-dwm-land

Tags replace workspaces. Each monitor owns a pair of real workspaces, visible
`100*(slot+1)+1` (first monitor: 101) and hidden `+1` (102). A window carries plain tags
`WMT<n>` plus one order tag `WMT_POS{n:rank,...}`. The *view* is the set of tags shown;
windows whose tags meet the view sit on the visible workspace, the rest are parked on the
hidden one. The scratchpad (`special:scratchpad`) is untagged by design and untouched.

The engine is a Lua module loaded by Hyprland's config as the global `hyprdwmland`. Every
operation is a Lua call made with `hyprctl eval`:

```bash
hyprctl eval 'hyprdwmland.view(3)'               # prints ok, or the Lua error
hyprctl eval 'return hl.get_current_submap()'    # "return" hands a value back
```

The whole Lua state is rebuilt on every config reload; only the state file survives.

## Read before you write

```bash
hyprctl eval 'hyprdwmland.debug()' && cat ~/.local/state/hypr-dwm-land/debug.txt
```

Every monitor's pair and view, every window with workspace, class, tags, rank and urgency,
per-tag layouts, focus memory, and the engine log. Cheaper reads:

```bash
grep '^view ' ~/.local/state/hypr-dwm-land/state
hyprctl clients -j | jq -r '.[]|select(.mapped)|[.address,.class,.workspace.id,(.tags|join(","))]|@tsv'
```

The live line for bars, one per monitor, on Hyprland's event socket:

```
custom>>hyprdwmland>>eDP-1|v=2,3|o=1:2,2:1,5:1|u=5|f=2   v viewed, o occupied tag:count, u urgent, f focused
custom>>hyprdwmland-reselect>>eDP-1|v=2,3                  a view op that landed on the current view
```

Capture with `socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock -`
through `grep --line-buffered`; plain grep holds its output until the socket closes.
`hyprdwmland.emit()` republishes the lines.

## Views

| call | effect |
|---|---|
| `view(3)` / `view({2,3})` | show exactly these tags |
| `toggleview(k)` | add or remove tag k from the view; refuses to empty it |
| `view_all()` | every tag; again returns to the previous view |
| `view_previous()` | the view before this one |
| `view_next(±1)` | next / previous tag that has windows |
| `winview()` | view = the focused window's tags |
| `focusurgent()` | view and focus the urgent window |
| `shiftview(±1)`, `shiftboth(±1)` | slide the view (and the window) one tag |

Tags are 1..21; 10..21 are the F-keys (F1 = 10). A combined view uses the lowest tag's layout
slot; the all view has its own. Every op takes an optional monitor name last. Views persist
across reloads and reboots.

## Windows

| call | effect |
|---|---|
| `tag({5}, w)` | replace w's tags (default w: the focused window) |
| `toggletag(k, w)` | add or remove one tag; refuses to remove the last |
| `tag_and_view(k, w)` | tag it k and go there |
| `tag_all(w)` | every tag |
| `sticky()` | pin the focused window |
| `tagmon(±1)` | send the focused window to the next monitor, retagged with that monitor's view |

`w` must be an `HL.Window`, not an address string:

```bash
hyprctl eval 'for _, w in ipairs(hl.get_windows()) do if w.class == "brave-browser" then hyprdwmland.tag({2}, w) end end'
```

Groups move as a unit. Windows left untagged outside the scratchpad are swept to tag 1 after
two seconds. A new window takes the tags of the view it opens in, even when spawned on the
hidden workspace.

## Layouts and names

`set_layout("master", { orientation = "center" })`, `cycle_layout(±1)`, `toggle_layout()`,
`rotate_layout_axis(±1)`, `mirror_layout()`, `toggle_gaps()`. A tag's layout is remembered
when you leave it; a tag never visited inherits the layout of the view you came from. Any
layout name Hyprland accepts works, including `lua:<name>` layouts registered in the config.

Tag names are a bar-widget setting, not engine state:

```bash
omarchy bar set person1873.hypr-dwm-land names '{"3":"web","4":"mail"}' --json
```

Middle-click on the widget opens the naming pane; `omarchy-shell shell toggle
person1873.hypr-dwm-land` does the same.

## Etiquette

- Every view change is on the user's screen. Say so before changing the view or tagging the
  user's windows for a test, and put the view back (`view_previous()`).
- Never spawn test windows bare; `hl.exec_cmd("foot -T name cmd", { workspace = "102" })`
  keeps them out of the scratchpad, and close them by address afterwards.
- Urgency: with Hyprland's `misc:focus_on_activate` on (Omarchy default) an activation request
  is a focus jump the engine follows; off, it becomes urgency (`u=` in the line).
- `wtype` cannot press Hyprland binds (its keys arrive as Escape); test binds through the Lua
  ops or ask the user.
- Multi-monitor tests: `hyprctl output create headless HEADLESS-1` / `output remove`; the
  pair becomes 201/202.

## Removal

`hyprctl eval 'hyprdwmland.uninstall()'` hands windows to workspaces numbered by their lowest
tag, then the `require` lines come out of `hyprland.lua`. Not something to run in passing.
