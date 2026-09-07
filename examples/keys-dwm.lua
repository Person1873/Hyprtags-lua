-- Hyprtags keys: the author's personal dwm map, carried over from a dwm-flexipatch build
-- (TAGKEYS with the COMBO patch, F-keys for tags 10..21, view-all toggle, focusurgent,
-- winview, sticky, shiftboth, tagmon, layout keys). These are one person's bindings, not
-- what dwm or flexipatch ship; edit to taste.
--
-- Use: copy to ~/.config/hypr/hyprtags-keys.lua and load with
--   require("hyprtags").setup({ keys = "hypr.hyprtags-keys" })
--
-- Omarchy chords displaced here (unbound by hyprtags.rebind, one per chord):
--   SUPER [+SHIFT[+ALT]] + 1..0        workspace switch / move / silent move
--   SUPER [+SHIFT|+CTRL] + TAB         next / previous / former workspace
--   SUPER + mouse_down / mouse_up      scroll workspaces
--   SUPER + O                          Pop window out  (kept on SUPER + ALT + O below)
--   SUPER + CTRL + LEFT / RIGHT        group prev / next (SUPER + ALT + TAB still cycles groups)
--   SUPER + SHIFT + S                  Google Maps web app

local T = hyprtags

local function tagkeys(key, k)
  local label = key:match("^code:") and tostring(k) or (tostring(k) .. " (" .. key .. ")")
  T.rebind("SUPER + " .. key, function() T.comboview(k) end, "View tag " .. label)
  T.rebind("SUPER + CTRL + " .. key, function() T.toggleview(k) end, "Toggle view of tag " .. label)
  T.rebind("SUPER + SHIFT + " .. key, function() T.combotag(k) end, "Tag window " .. label)
  T.rebind("SUPER + CTRL + SHIFT + " .. key, function() T.toggletag(k) end, "Toggle window tag " .. label)
end

for k = 1, 9 do
  tagkeys("code:" .. tostring(k + 9), k)                          -- digits 1..9
  T.unbind("SUPER + SHIFT + ALT + code:" .. tostring(k + 9))      -- Omarchy silent move
end
for k = 10, 21 do tagkeys("F" .. tostring(k - 9), k) end      -- F1..F12
T.combo_enable("SUPER")                                        -- releasing SUPER ends a combo

T.rebind("SUPER + code:19", function() T.view_all() end, "View all tags (again: previous view)")
T.rebind("SUPER + SHIFT + code:19", function() T.tag_all() end, "Tag window with all tags")
T.unbind("SUPER + SHIFT + ALT + code:19")

T.rebind("SUPER + TAB", function() T.view_previous() end, "View previous tags")
T.unbind("SUPER + SHIFT + TAB")
T.unbind("SUPER + CTRL + TAB")
T.unbind("SUPER + mouse_down")
T.unbind("SUPER + mouse_up")

T.rebind("SUPER + U", function() T.focusurgent() end, "Focus urgent window")
T.rebind("SUPER + O", function() T.winview() end, "View the focused window's tags")
hl.bind("SUPER + ALT + O", hl.dsp.exec_cmd("omarchy-hyprland-window-pop"), { description = "Pop window out (float & pin)" })
T.rebind("SUPER + SHIFT + S", function() T.sticky() end, "Toggle sticky (pin)")
T.rebind("SUPER + CTRL + LEFT", function() T.shiftboth(-1) end, "Shift window and view to previous tag")
T.rebind("SUPER + CTRL + RIGHT", function() T.shiftboth(1) end, "Shift window and view to next tag")
T.rebind("SUPER + SHIFT + comma", function() T.tagmon(-1) end, "Send window to previous monitor")
T.rebind("SUPER + SHIFT + period", function() T.tagmon(1) end, "Send window to next monitor")

-- Layouts, from the dwm layouts[] slots and their keys. Slot 0 tile → master, slot 2
-- monocle → monocle, slot 3 columns → scrolling; slot 1 (floating "layout") has no
-- Hyprland equivalent, so SUPER+SHIFT+Y keeps Omarchy's YouTube. Per-tag memory and the
-- notification live in the engine. Displaced: Music (SHIFT+M), Calendar (SHIFT+C),
-- Activity (CTRL+T), Herdr (CTRL+RETURN; Herdr lives on SUPER+RETURN in the app layer), Herdr keybindings
-- (CTRL+K), and the personal "swap with master" on SHIFT+SPACE (zoom is SHIFT+RETURN).
T.rebind("SUPER + SHIFT + T", function() T.set_layout("master", { orientation = "left" }) end, "Layout: master (tile)")
T.rebind("SUPER + SHIFT + M", function() T.set_layout("monocle") end, "Layout: monocle")
T.rebind("SUPER + SHIFT + C", function() T.set_layout("scrolling") end, "Layout: scrolling (columns)")
T.rebind("SUPER + SHIFT + SPACE", function() T.toggle_layout() end, "Layout: previous")
T.rebind("SUPER + CTRL + T", function() T.rotate_layout_axis(1) end, "Rotate master orientation")
T.rebind("SUPER + CTRL + RETURN", function() T.mirror_layout() end, "Mirror master and stack")
T.rebind("SUPER + CTRL + J", function() hl.dispatch(hl.dsp.layout("rollnext")) end, "Roll stack forward")
T.rebind("SUPER + CTRL + K", function() hl.dispatch(hl.dsp.layout("rollprev")) end, "Roll stack backward")
T.rebind("SUPER + ALT + code:19", function() T.toggle_gaps() end, "Toggle gaps")
