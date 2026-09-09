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

## A verification failure, recorded

The cursor-warp fix (2026-09-08) introduced `focus_window` above the helper it calls, so
inside Hyprland's Lua state the helper resolved as a nil global and every view change
aborted at its first focus call. The error was caught by `reconcile`'s `pcall` and logged
as "reconcile failed", which the AI's test harness never counted (it grepped for "ERROR").
The cursor test therefore "passed" because no focus happened at all, and later placement
tests passed because placement was unaffected. Found on a full read of the code the human
asked for before submission, confirmed from the log, fixed, and re-tested with focus and
cursor position checked together. Lesson recorded: a test that checks one side effect
cannot vouch for the operation that produces it.

## Omarchy dependence, narrowed

The human asked what stopped this being a generic Hyprland plugin. Answer after audit:
one notification call in the engine (replaced with Hyprland's own overlay) and nothing
else; the widget, installer and finder are the Omarchy layer. The README gained a
"Without Omarchy" section with the two-step install and the bar protocol, and
`examples/waybar-tags.sh` shows the protocol consumed by a different bar. That script's
parsing was run against the live socket; waybar itself was not installed to try it.

## No installer

The human asked why the marketplace baseline reported an `installer` capability when the
plugin is "just a require". Answer: the scanner flags any file named install/setup/
uninstall, and the two scripts were the only thing keeping the baseline from `passed`.
Omarchy's own CLI (`plugin add --enable`, `bar put`, `plugin disable`) does the widget
placement, so the scripts were removed and the README now gives the three commands and the
three `hyprland.lua` lines instead. The engine still edits nothing.

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

Tested on a headless second output (`hyprctl output create headless`, 2026-09-08): pair
201/202 created and persisted, a window opening there taking its view, `tagmon` both ways,
a silent cross-monitor move retagged to the destination's view, Omarchy's move-workspace-to-
monitor bounced back within 50 ms, removal landing orphaned windows in the survivor's
parking lot with tags intact, one bar event line per monitor. Also found there and fixed:
the bounce guard disabled itself on monitor removal (Hyprland reports the migration as a
move while the dead monitor is still listed).

Not tested: a physical second monitor (hot-plug timing, scale, DPMS), the shipped
Omarchy-flavoured keys module loaded live, the finder's picker interaction, bar clicks
(the tag-click path was exercised by the human, who found the cursor warp).

## Errors made and corrected along the way

Recorded because they are the kind of thing an AI gets confidently wrong:

- An earlier note claimed Hyprland's Lua API had no silent move and no window selector on
  `window.move`. Both exist; the note came from probing with junk values, which selector
  keys ignore until dispatch time. Corrected from source.
- The initial view seeding bug (`ensure_pair` defaulting the view before the fresh-install
  fallback ran) and a `window.destroy` handler that indexed a table with a nil address.
- A test used a `pid:` selector and moved the wrong Brave window; `pid:` matches the first
  window of a process.

## Reselect event (2026-09-08, dev)

Selecting the view already shown left the bar line unchanged, so a companion that answers
selections (just-hyprtonation) heard nothing; the human found that unsettling ("makes me
feel like it didn't work"). `set_view` now also dispatches
`hyprdwmland-reselect>><monitor>|v=<tags>` in that case. The bar widget and the waybar
example filter on the `hyprdwmland>>` prefix and ignore it; verified on the socket.

## Update after publication (2026-09-09, dev)

Published and maintainer-verified at `e7559f5` on 2026-09-08. For the first update the AI
proposed keeping the installer scripts out (as `dev` had them) so the baseline would come
back `passed`; the human kept them ("since they've already been approved, there's no need
to remove the installer scripts anymore", and their bytes are unchanged from the approved
commit), so they are restored from `main` and the README leads with Omarchy's own commands
and offers the scripts as the alternative. Also added at the human's "in principle yes":
version 0.2.0, FAQ entries on mouse drags across monitors and on `focus_on_activate`, and a
Companions section.

## Tag names and agent skills (2026-09-09, dev)

The human wanted the update to carry more than the reselect event: "a settings pane for the
tag widget which allows naming/renaming of tags with full unicode support". Design by the
AI after reading the shell: names are a widget setting (`names` object in the widget's
shell.json entry), written through the shell's `setBarWidget` IPC, the same path as
`omarchy bar set … --json`, so the engine, the keys and the socket protocol are untouched
and other bars keep their numbers. `shell/Names.qml` is a popout hosted by the widget in the
first-party pattern (weather, clock): middle-click or `omarchy-shell shell toggle` opens it,
one field per tag, Tab/Return/Escape. A named tag shows its name in the bar with the focus
glyph in front rather than in place. Tested: names set from the CLI in Latin, Cyrillic and
an emoji appeared in the bar; the pane opened clean; a name typed into the pane through
wtype landed in shell.json and the bar. Mouse editing in the pane was not exercised by the AI.

The human also asked for skills, "omarchy is also AI first": `agents/skills/hypr-dwm-land`
(using it) and `agents/skills/hypr-dwm-land-dev` (working on it), linked the way Omarchy's
migrations link its own skills into the agents' skill directories.

## alttags (2026-09-09, dev)

The human recalled dwm's alttags ("you held a key and it showed you the tag numbers") as
the complement of names. First attempt, binds on `SUPER + Super_L` with and without the
release flag: a capture of the human's presses showed Hyprland fires a lone-modifier bind
only at release, both variants three milliseconds apart, and not at all when another key
followed, so a bind cannot report the modifier going down. Second attempt, polling
`hl.is_key_down`: the 0.56.2 keybind manager pushes every key press, modifiers included,
into the pressed-keys list with keycode evdev + 8, so the engine polls 133 and 134 every
80 ms and announces transitions; the widget shows numbers while down. The widget half was
verified by injecting the event and screenshotting the bar. The poll half was written from
the source while the human was away, then verified without hands: wtype's virtual key
enters the same pressed-keys list under keycode 9, so with the poll pointed at 9 for two
seconds a held virtual key produced `down` 35 ms after the press and `up` 50 ms after the
release (Escape sunk by a throwaway bind meanwhile). What remains assumed is only that
left and right Super are 133 and 134, KEY_LEFTMETA and KEY_RIGHTMETA plus eight.

## Order on master tags (2026-09-09, dev)

The human: "I thought we preserved window ordering per tag". The snapshot was right; the
re-show assumed Hyprland's default `master.new_status = slave`, where a re-inserted window
joins the stack, but Omarchy ships `new_status = master`, where every arrival becomes the
master and the previous one heads the stack, so rank 1 then rank 2 came back as 2 over 1.
The re-show now reads `master.new_status` and `new_on_top` through `hl.get_config` and
inserts in the order that lands 1..N under each setting (reverse for master or inherit;
rank 1 then the rest reversed for slave with new_on_top). Found alongside: the snapshot
sorted by left-to-right position whatever the master orientation, which misreads centre,
right and bottom; it now sorts by the orientation in force, with the widest tiled window as
the centre master. First attempt broke every reconcile on a forward reference (the slot
helper was defined below its first use); the engine log said so at once, and the fix is a
forward declaration. Verified: two round trips off tag 1 (master, two windows) and back
kept rank 1 as master both times, no failures logged. The human's reversal itself was not
reproduced by the AI before the fix; the mechanism is from Omarchy's setting and Hyprland's
documented behaviour.
