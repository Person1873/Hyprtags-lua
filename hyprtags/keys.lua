-- Hyprtags default keys: Omarchy's own workspace chords, mapped onto tags.
--
-- Loaded by require("hyprtags").setup({}) after the engine is up. To customise, copy this
-- file to ~/.config/hypr/hyprtags-keys.lua, edit it, and load that instead:
--   require("hyprtags").setup({ keys = "hypr.hyprtags-keys" })
-- The author's personal dwm-style map lives in the repo under examples/keys-dwm.lua.
--
-- Every bind on a key fires, so each Omarchy chord being replaced is unbound first;
-- hyprtags.rebind does exactly that, one chord at a time, and reports failures.
--
-- Omarchy default            here
--   SUPER + n                 switch to workspace n   -> view tag n
--   SUPER + SHIFT + n         move window to n        -> tag n and follow (view n)
--   SUPER + SHIFT + ALT + n   move silently to n      -> tag n, stay
--   SUPER + 0                 workspace 10            -> tag 10
--   SUPER + TAB / SHIFT + TAB next / previous ws      -> next / previous occupied tag
--   SUPER + CTRL + TAB        former workspace        -> previous view
--   SUPER + mouse_down/up     scroll workspaces       -> next / previous occupied tag
-- Added (no Omarchy chord on these keys):
--   SUPER + CTRL + n          toggle tag n in the view
--   SUPER + CTRL + SHIFT + n  toggle tag n on the focused window

local T = hyprtags

for k = 1, 10 do
  local key = "code:" .. tostring(k + 9) -- code:10 = "1" ... code:18 = "9", code:19 = "0"
  T.rebind("SUPER + " .. key, function() T.view(k) end, "View tag " .. k)
  T.rebind("SUPER + SHIFT + " .. key, function() T.tag(k); T.view(k) end, "Move window to tag " .. k)
  T.rebind("SUPER + SHIFT + ALT + " .. key, function() T.tag(k) end, "Move window silently to tag " .. k)
  T.rebind("SUPER + CTRL + " .. key, function() T.toggleview(k) end, "Toggle view of tag " .. k)
  T.rebind("SUPER + CTRL + SHIFT + " .. key, function() T.toggletag(k) end, "Toggle window tag " .. k)
end

T.rebind("SUPER + TAB", function() T.view_next(1) end, "Next tag")
T.rebind("SUPER + SHIFT + TAB", function() T.view_next(-1) end, "Previous tag")
T.rebind("SUPER + CTRL + TAB", function() T.view_previous() end, "Former tags")
T.rebind("SUPER + mouse_down", function() T.view_next(1) end, "Scroll to next tag")
T.rebind("SUPER + mouse_up", function() T.view_next(-1) end, "Scroll to previous tag")
