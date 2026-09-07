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

- All code: `hyprdwmland/init.lua`, `hyprdwmland/keys.lua`, `examples/keys-dwm.lua`,
  `shell/Tags.qml`, `manifest.json`, `bin/hypr-dwm-land-windows`, `install.sh`, this README set.
- The API facts the design rests on were checked against Hyprland v0.56.2 source
  (`LuaBindingsDispatchers.cpp`, `LuaBindingsInternal.cpp`, `ConfigActions.cpp`,
  `TagKeeper.cpp`, `EventManager.cpp`, `ConfigManager.cpp`) and Quickshell 0.3.1 source, not
  from memory. Where a claim could not be verified it is marked as such in the README.
- Engineering choices the human accepted rather than specified: workspace ids 101/102 per
  monitor slot; rank snapshotted at hide time from geometry rather than tracked live
  (proposed as the simpler of three options); the socket2 `custom>>hyprdwmland>>…` protocol
  and its debounce; per-view focus memory; the bounce guard that disables itself; per-chord
  key registration under `pcall`; Ctrl as the bar's click modifier because SUPER+mouse is
  consumed by Omarchy's global drag bind; the `omarchy-menu-select` based window finder;
  the focus-or-launch browser key that reads the class from the xdg default browser's
  desktop entry.
- The senior-dev style review of the code and the list of ordering hazards.

## Marketplace hardening pass (2026-09-08)

Prompted by the human asking whether the plugin had been submitted to the Omarchy plugin
marketplace. The AI read the marketplace's submission guide, security baseline and the
community review-pitfalls guide, then changed: the state file from executed Lua to a
parsed, bounded line format; the widget to accept the monitor name only from a closed
grammar; the window finder to strip markup and control characters from titles, bound the
`hyprctl` output and validate addresses; `install.sh` to write one marked block with
rollback and same-directory temporaries; a new `uninstall.sh` that removes only that block.
The README was rewritten for readers who do not know dwm, at the human's request.

## External review

A second AI session the human runs (the one whose conversation prompted this project)
reviewed the repository and reported that the geometry-based rank snapshot collapses to
address order in monocle, where every tiled window has the same box, so a stack roll made
on a monocle tag was discarded on the next view change. Correct. The fix chosen here (keep
the ranks the windows already carry when the layout is monocle; only the cyclic order
matters there because re-show inserts by rank and focus memory restores the top window)
differs from the suggested one (snapshot on the roll dispatchers) and was verified live
with ranks deliberately out of address order.

## Name

Started as "Hyprtags". Renamed to hypr-dwm-land on 2026-09-08, the human's choice, after
the AI found `JoaoCostaIFG/hyprtags`, an active C++ Hyprland plugin with the same goal whose
Lua API even lives at `hl.plugin.hyprtags.*`. The human raised the collision. The Lua
identifier is `hyprdwmland` because Lua names cannot carry dashes.

## What is borrowed

The tag model, operation names and the behaviour of the pertag, combo, hidevacanttags,
winview, shiftboth, focusurgent and tagmon patches come from dwm and its patch ecosystem.
No dwm source was opened during this project, but the AI that wrote the code has dwm and
its patches in its training data and recalled specific behaviour from that memory (the
pertag lowest-tag rule, combo semantics, dwm's same-tagset no-op in `view`). The human
raised this point; the earlier wording "reimplemented from description" was the AI's and
understated it. No dwm code is reproduced or structurally translated; the model here is
Hyprland's, not dwm's. See "Prior art and credit" in the README.

## Tested versus untested (as of the first public push)

Tested live on one laptop (Omarchy 4.0.2, Hyprland 0.56.2, Quickshell 0.3.1): adoption,
rank snapshot and restoration after a swap, hidden-workspace bounce, adoption from numbered
workspaces, scratchpad round trip, view survival across `hyprctl reload`, digit combos with
modifier release, focus memory, stray adoption, F-key tags, SUPER+0 toggle, the default
browser and mail keys revealing hidden windows, the finder's listing, per-tag layouts
(seeding from Omarchy's files, switching, cycling, combined views taking the lowest tag's
layout), the layout keys (set, toggle back, rotate, mirror, gaps), floating windows keeping
their geometry through park and return, monocle parking sizes, tabbed groups moving as one
unit and taking the union of their members' tags when formed by hand.

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
