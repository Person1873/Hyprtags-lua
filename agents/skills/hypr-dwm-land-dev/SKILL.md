---
name: hypr-dwm-land-dev
description: "Hack on hypr-dwm-land itself: the Lua engine, the Quickshell tags widget and its naming pane, the key maps, the bar protocol, tests and release. Use when editing files in the hypr-dwm-land repository or debugging its behaviour, not merely for using tags (see the hypr-dwm-land skill)."
---

# Hacking on hypr-dwm-land

Read `AUTHORSHIP.md` first: it records what was tested, what was not, and every decision
that was made by ear or by the user rather than by principle.

## Layout of the repo

| path | what |
|---|---|
| `hyprdwmland/init.lua` | the engine, ~1900 lines; `setup(opts)` at the end |
| `hyprdwmland/keys.lua` | default key map (Omarchy's chords pointed at tags) |
| `examples/keys-dwm.lua` | the dwm map; `examples/waybar-tags.sh` a bar for non-Omarchy |
| `shell/Tags.qml` | the bar widget; `shell/Names.qml` the naming pane it hosts |
| `bin/hypr-dwm-land-windows` | window finder over `omarchy-menu-select` |
| `manifest.json` | Omarchy plugin manifest, kind `bar-widget` |
| `install.sh`, `uninstall.sh` | optional; Omarchy's CLI does the same |
| `agents/skills/` | these skills |

## How the engine is put together

- **Pairs**: `ensure_pair` allocates `vis`/`hid` per monitor name and registers workspace
  rules (hidden gets `layout = "monocle"`). Ids persist in the state file.
- **Tag codec**: `read_tags(w)` / `write_tags` over Hyprland's window tags via
  `hl.dsp.window.tag({ tag = "+WMT3", window = w })` (+ set, − unset). Never `clear_tags`:
  it destroys Omarchy's own rule tags.
- **Reconcile**: `reconcile(mon, opts)` moves mismatched windows between the pair with
  `follow = false`, re-shows in rank order with chained focus, restores fullscreen, then
  `fix_focus`. Guarded by `busy` and a per-monitor `dirty` re-run.
- **Ranks**: `snapshot_ranks` records stack position from geometry when a window is hidden;
  under monocle existing ranks are kept.
- **Layouts**: per view slot (`layout_key`: lowest tag, or `all`), applied by workspace rule
  (lands ~300 ms later, async; `layout_settling` stops recording the transient).
- **Events**: `hl.on(...)` handlers for open/close/destroy/active/urgent/move/workspace
  active/config reload/monitor add-remove/workspace move-to-monitor. Window handles can be
  dead by the time a handler runs: read `address` under `pcall`.
- **Bar IPC**: `emit_line` builds `hyprdwmland>>mon|v=|o=|u=|f=`; debounced 30 ms;
  `set_view` sends `hyprdwmland-reselect>>` when the requested view equals the current.
- **State file**: `~/.local/state/hypr-dwm-land/state`, line records
  `slot|view|prev|focus|layout`, 64 KiB cap, re-read on reload and checked against reality.
- **Keys**: `bind/unbind/rebind` with failures collected for `debug()`; the keys module is
  named in `setup({ keys = "module" })` and required through `package.path`.

## Verified Hyprland facts (0.56.x), do not re-derive

- The Lua state is destroyed on every tracked-file change; `hl.on`, timers, binds and
  workspace rules all vanish; window tags and placement survive.
- `hl.workspace_rule` and `hl.config` apply live; rules land asynchronously.
- `hl.dsp.window.move({ workspace, follow = false, window })` is the silent move.
- `hyprctl eval 'return expr'` returns values; `error()` messages are precise.
- Tag matching is exact string equality; `hl.get_windows({ tag = })` matches the same way.
- `hl.exec_cmd(cmd, { workspace = "102" })` spawns on a workspace.
- Release binds match only the modifiers held at the press; `ignore_mods = true` frees a key
  whatever the modifiers. `hl.is_key_down(keycode)` takes evdev + 8 and sees modifier keys
  too (every press is pushed to the pressed-keys list before binds run).
- A bind on a lone modifier (`SUPER + Super_L`) fires only at its release, and not at all
  when another key was pressed in between; poll `is_key_down` to see a modifier go down.
- Headless outputs (`hyprctl output create headless NAME`) are real monitors for testing.

## Testing

- Spawn on the hidden workspace: `hl.exec_cmd("foot -T t1 sleep 600", { workspace = "102" })`,
  then retag through a Lua lookup by title. Close by address.
- Watch the socket with `socat … | grep --line-buffered`; count `failed` as well as `ok` in
  any harness (a nil global once made every view change abort silently while tests passed
  on the cursor alone).
- Widget or pane changes need `omarchy restart shell`; the hot reload leaves the loaded
  component stale. A panel entry point in a subdirectory failed to load ("File name case
  mismatch"); keep QML entry points where the manifest already puts them.
- `wtype` drives a focused Quickshell surface but not Hyprland binds.
- `omarchy plugin validate .` before committing; it prints nothing on success.

## Release

`main` is what the marketplace lists; work lands on `dev` and is fast-forwarded. A marketplace
update is a `[Verify]:` issue with the full SHA (see the marketplace's SUBMISSION.md). Bump
`version` in `manifest.json`. Record decisions and tests in `AUTHORSHIP.md` as they happen.
