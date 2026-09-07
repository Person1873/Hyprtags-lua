# Authorship

This project was built in a pair-programming session between Person1873 and an AI
assistant (Claude, Anthropic) on 2026-09-07/08. This file says who decided what, so a reader
can tell design intent from generated implementation, and what has actually been tested.

## Human-driven (design and decisions)

- The concept: replace Hyprland workspaces with dwm-style tags, implemented purely in
  Hyprland's Lua config, using a pair of real workspaces per monitor (visible + hidden) and
  Hyprland's own per-window tags as the semaphore. Keep the scratchpad as it is.
- Tags carry ordering data, not just membership.
- The final tag schema: plain `WMT<n>` membership tags so Hyprland's rule engine can match
  them, plus a separate `WMT_POS{n:rank}` position tag. Proposed by the human after the AI
  had argued for a compound form; the AI's compound schema was dropped as inferior.
- Key map follows the human's own dwm-flexipatch `config.h` (read from their workstation),
  including the COMBO patch behaviour, MOD+0 toggling back, and F1..F12 as tags 10..21.
  Omarchy chords in the way get out of the way.
- App keys go through Omarchy's default-app selectors, never hard-coded binaries.
- Keys live in a pluggable module; the shipped default mirrors Omarchy's own chords, the
  dwm map is an example the user copies into `~/.config`.
- Any untagged window outside the scratchpad gets tag 1 (a review item the human promoted
  to a merge blocker), and the decision to work through the remaining review items.
- The bar replaces `omarchy.workspaces`, looks like it, hides empty tags, keeps dwm buttons.
- Publish as an Omarchy plugin under the MIT licence.
- Per-tag layouts, prompted by the human asking what the "workspaces 1..99 stay free" claim
  was missing (their dwm build had PERTAG); the lowest-tag rule for combined views was the
  AI's answer to the human's question about what a combo would select. The layout keys
  (tile/monocle/columns slots, previous-layout toggle, axis rotate, mirror, stack roll,
  gaps toggle) come from the human's dwm `layouts[]` table and key list; the mapping of
  dwm's flextile slots onto Hyprland's master/monocle/scrolling is the AI's.

## AI-generated (implementation and analysis)

- All code: `hyprtags/init.lua`, `hyprtags/keys.lua`, `examples/keys-dwm.lua`,
  `shell/Tags.qml`, `manifest.json`, `bin/hyprtags-windows`, `install.sh`, this README set.
- The API facts the design rests on were checked against Hyprland v0.56.2 source
  (`LuaBindingsDispatchers.cpp`, `LuaBindingsInternal.cpp`, `ConfigActions.cpp`,
  `TagKeeper.cpp`, `EventManager.cpp`, `ConfigManager.cpp`) and Quickshell 0.3.1 source, not
  from memory. Where a claim could not be verified it is marked as such in the README.
- Engineering choices the human accepted rather than specified: workspace ids 101/102 per
  monitor slot; rank snapshotted at hide time from geometry rather than tracked live
  (proposed as the simpler of three options); the socket2 `custom>>hyprtags>>…` protocol
  and its debounce; per-view focus memory; the bounce guard that disables itself; per-chord
  key registration under `pcall`; Ctrl as the bar's click modifier because SUPER+mouse is
  consumed by Omarchy's global drag bind; the `omarchy-menu-select` based window finder;
  the focus-or-launch browser key that reads the class from the xdg default browser's
  desktop entry.
- The senior-dev style review of the code and the list of ordering hazards.

## What is borrowed

Design only. The tag model, operation names and the behaviour of the pertag, combo,
hidevacanttags, winview, shiftboth, focusurgent and tagmon patches come from dwm and its
patch ecosystem, reimplemented from their documented behaviour. No dwm code was read into
this project or translated; see "Prior art and credit" in the README.

## Tested versus untested (as of the first public push)

Tested live on one laptop (Omarchy 4.0.2, Hyprland 0.56.2, Quickshell 0.3.1): adoption,
rank snapshot and restoration after a swap, hidden-workspace bounce, adoption from numbered
workspaces, scratchpad round trip, view survival across `hyprctl reload`, digit combos with
modifier release, focus memory, stray adoption, F-key tags, SUPER+0 toggle, the default
browser and mail keys revealing hidden windows, the finder's listing, per-tag layouts
(seeding from Omarchy's files, switching, cycling, combined views taking the lowest tag's
layout), the layout keys (set, toggle back, rotate, mirror, gaps).

Not tested: anything with a second monitor (pair 201/202, `tagmon`, monitor removal, the
move-workspace-to-monitor bounce), the shipped Omarchy-flavoured keys module loaded live,
the finder's picker interaction, bar clicks.

## Errors made and corrected along the way

Recorded because they are the kind of thing an AI gets confidently wrong:

- An earlier note claimed Hyprland's Lua API had no silent move and no window selector on
  `window.move`. Both exist; the note came from probing with junk values, which selector
  keys ignore until dispatch time. Corrected from source.
- The initial view seeding bug (`ensure_pair` defaulting the view before the fresh-install
  fallback ran) and a `window.destroy` handler that indexed a table with a nil address.
- A test used a `pid:` selector and moved the wrong Brave window; `pid:` matches the first
  window of a process.
