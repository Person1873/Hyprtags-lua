-- Hyprtags: DWM-style tags for Hyprland's Lua config (Omarchy).
--
-- Model
--   * Per monitor a pair of real workspaces: `vis` (the only one ever focused) and `hid`
--     (parking lot). Windows outside the current view are moved to `hid` silently.
--   * Membership lives in Hyprland's own window tags: `WMT3`, `WMT5` (exact names, so
--     window rules and hl.get_windows({ tag = "WMT3" }) can match them).
--   * Stack position lives in one more tag, `WMT_POS{3:1,5:2}` (tag:rank pairs), snapshotted
--     from on-screen geometry when a window is hidden. Re-showing a tag re-inserts its
--     windows lowest rank first, so a stack comes back as it was left.
--   * `special:scratchpad` is untouched.
--
-- Everything the compositor needs to survive a config reload (tags, workspace placement)
-- is compositor state; the small remainder (slot per monitor, current/previous view) is
-- in ~/.local/state/hyprtags/state (a passive line format, parsed, never executed).
--
-- Public surface (also reachable via `hyprctl eval 'hyprtags.view(3)'`): see the `M.*`
-- functions near the bottom.

local M = {}
_G.hyprtags = M

local HOME = os.getenv("HOME") or ""
local unpack = table.unpack or unpack

-- ---------------------------------------------------------------------------------------
-- Configuration
-- ---------------------------------------------------------------------------------------

local cfg = {
  ntags = 21,           -- 1..9 on digits; a keys module may put 10..21 on F1..F12
  state_dir = HOME .. "/.local/state/hyprtags",
  -- Lua module that binds the keys, loaded after the engine is up. The shipped
  -- "hyprtags.keys" maps Omarchy's own chords onto tags. Copy it to
  -- ~/.config/hypr/hyprtags-keys.lua, edit, and pass keys = "hypr.hyprtags-keys".
  -- false = bind nothing (Omarchy's workspace keys then stay in force).
  keys = "hyprtags.keys",
  stray_sweep = 2000,   -- ms: adopt untagged windows this often (0 = only on changes)
  stray_tag = 1,        -- untagged windows outside the scratchpad land here
  combo_timeout = 1000, -- ms: fallback for the modifier-release detection
  emit_delay = 30,      -- ms: debounce for bar events
  -- Per-tag layouts (dwm PERTAG): the visible workspace's layout is remembered per view
  -- and re-applied when that view returns. cycle_layout(±1) walks this list.
  layouts = {
    { layout = "dwindle" },
    { layout = "master", opts = { orientation = "left" } },
    { layout = "master", opts = { orientation = "center" }, name = "centre master" },
    { layout = "monocle" },
    { layout = "scrolling" },
  },
  -- Seed per-tag layouts once from Omarchy's per-workspace files (workspace n -> tag n).
  omarchy_layouts_dir = HOME .. "/.local/state/omarchy/workspace-layouts",
}

-- ---------------------------------------------------------------------------------------
-- Runtime state (rebuilt on every config reload)
-- ---------------------------------------------------------------------------------------

local pairs_by_mon = {}   -- monname -> { vis = id, hid = id, slot = n }
local mon_of_ws = {}      -- ws id -> monname
local view = {}           -- monname -> { [tag] = true }
local prev = {}           -- monname -> { [tag] = true } | nil
local slots = {}          -- monname -> slot
local urgent = {}         -- address -> true
local fs_state = {}       -- address -> fullscreen mode saved at hide
local busy = false
local dirty = {}
local emit_timer = nil
local combo = { active = false, timer = nil }
local log_lines = {}
local lastfocus = {}      -- monname -> { [viewkey] = address }  (address of the window to refocus)
local layouts = {}        -- monname -> { [slot] = { layout = name, opts = {...}|nil } }
local prev_layout = {}    -- monname -> { [slot] = previous record }  (dwm setlayout toggle)
local layout_settling = {} -- monname -> true while a workspace_rule we issued is taking effect
local gaps_saved = nil    -- { gaps_in, gaps_out } while gaps are toggled off
local pending = {}        -- monname -> true while a deferred reconcile is queued
local bounce_block = {}   -- ws id -> true while a move_to_monitor bounce is cooling down
local bounce_disabled = false
local bind_failures = {}  -- "keys: error" strings from the last keys-module load

local function log(fmt, ...)
  local line = os.date("%H:%M:%S ") .. string.format(fmt, ...)
  log_lines[#log_lines + 1] = line
  if #log_lines > 400 then table.remove(log_lines, 1) end
end

-- At most one toast per distinct message every `notify_every` seconds; the log keeps
-- every occurrence.
local notify_seen = {}
local function notify(text)
  local key = text:sub(1, 60)
  local now = os.time()
  if notify_seen[key] and now - notify_seen[key] < 10 then return end
  notify_seen[key] = now
  pcall(function()
    hl.notification.create({ text = "hyprtags: " .. text, timeout = 6000 })
  end)
end

local function guard(name, fn)
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok then
      log("ERROR in %s: %s", name, tostring(err))
      notify(name .. ": " .. tostring(err))
    end
  end
end

local function dispatch(d)
  local ok, err = pcall(hl.dispatch, d)
  if not ok then log("dispatch failed: %s", tostring(err)) end
  return ok
end

-- ---------------------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------------------

local function set_of(list)
  local s = {}
  for _, k in ipairs(list) do s[k] = true end
  return s
end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end

local function set_empty(s)
  return next(s) == nil
end

local function set_eq(a, b)
  for k in pairs(a) do if not b[k] then return false end end
  for k in pairs(b) do if not a[k] then return false end end
  return true
end

local function set_copy(s)
  local c = {}
  for k, v in pairs(s) do c[k] = v end
  return c
end

local function intersects(a, b)
  for k in pairs(a) do if b[k] then return true end end
  return false
end

local function all_tags()
  local s = {}
  for k = 1, cfg.ntags do s[k] = true end
  return s
end

local function min_key(s)
  local m
  for k in pairs(s) do if not m or k < m then m = k end end
  return m
end

local function wsel(w)
  return "address:" .. tostring(w.address)
end

local function ws_id(w)
  local ws = w.workspace
  return ws and ws.id or nil
end

local function is_special(w)
  local ws = w.workspace
  return ws ~= nil and (ws.special or ws.id < 0)
end

-- ---------------------------------------------------------------------------------------
-- Tag codec
-- ---------------------------------------------------------------------------------------

-- Returns members = { [tag]=true }, pos = { [tag]=rank }, posraw = the WMT_POS string or nil.
local function read_tags(w)
  local members, pos, posraw = {}, {}, nil
  local tags = w.tags
  if type(tags) ~= "table" then return members, pos, posraw end
  for _, t in ipairs(tags) do
    local k = t:match("^WMT(%d+)$")
    if k then
      members[tonumber(k)] = true
    else
      local body = t:match("^WMT_POS{(.*)}$")
      if body then
        posraw = t
        for tk, rk in body:gmatch("(%d+):(%d+)") do
          pos[tonumber(tk)] = tonumber(rk)
        end
      end
    end
  end
  return members, pos, posraw
end

local function pos_string(pos)
  local parts = {}
  for _, k in ipairs(sorted_keys(pos)) do
    parts[#parts + 1] = k .. ":" .. pos[k]
  end
  if #parts == 0 then return nil end
  return "WMT_POS{" .. table.concat(parts, ",") .. "}"
end

local function tag_op(w, str)
  dispatch(hl.dsp.window.tag({ tag = str, window = wsel(w) }))
end

-- Write the desired membership + positions with the minimum number of tag operations.
local function write_tags(w, members, pos)
  local cur, _, curposraw = read_tags(w)
  for k in pairs(cur) do
    if not members[k] then tag_op(w, "-WMT" .. k) end
  end
  for k in pairs(members) do
    if not cur[k] then tag_op(w, "+WMT" .. k) end
  end
  -- positions only for tags the window is a member of
  local clean = {}
  for k, r in pairs(pos) do if members[k] then clean[k] = r end end
  local want = pos_string(clean)
  if want ~= curposraw then
    if curposraw then tag_op(w, "-" .. curposraw) end
    if want then tag_op(w, "+" .. want) end
  end
end

local function is_managed(w)
  local m = read_tags(w)
  return not set_empty(m)
end

-- ---------------------------------------------------------------------------------------
-- Monitors and workspace pairs
-- ---------------------------------------------------------------------------------------

local function pair_ids(slot)
  local vis = 100 * (slot + 1) + 1
  return vis, vis + 1
end

local function next_free_slot()
  local used = {}
  for _, s in pairs(slots) do used[s] = true end
  local s = 0
  while used[s] do s = s + 1 end
  return s
end

local function register_rules(monname, vis, hid)
  pcall(hl.workspace_rule, { workspace = tostring(vis), monitor = monname, persistent = true, default = true })
  pcall(hl.workspace_rule, { workspace = tostring(hid), monitor = monname, persistent = true })
end

local save_state -- forward

local function ensure_pair(monname)
  local p = pairs_by_mon[monname]
  if p then return p end
  local slot = slots[monname]
  if slot == nil then
    slot = next_free_slot()
    slots[monname] = slot
    save_state()
  end
  local vis, hid = pair_ids(slot)
  p = { vis = vis, hid = hid, slot = slot }
  pairs_by_mon[monname] = p
  mon_of_ws[vis] = monname
  mon_of_ws[hid] = monname
  register_rules(monname, vis, hid)
  view[monname] = view[monname] or { [1] = true }
  return p
end

local function monitor_by_name(name)
  for _, m in ipairs(hl.get_monitors()) do
    if m.name == name then return m end
  end
  return nil
end

local function active_monname()
  local m = hl.get_active_monitor()
  return m and m.name or nil
end

-- Monitor a window belongs to for tag purposes (by its workspace pair, else by monitor).
local function monname_of(w)
  local id = ws_id(w)
  if id and mon_of_ws[id] then return mon_of_ws[id] end
  local m = w.monitor
  return m and m.name or nil
end

local function monitors_sorted()
  local ms = hl.get_monitors()
  table.sort(ms, function(a, b)
    if a.x ~= b.x then return a.x < b.x end
    return a.y < b.y
  end)
  return ms
end

-- ---------------------------------------------------------------------------------------
-- Persistent state
-- ---------------------------------------------------------------------------------------

-- State file format (hyprtags/state, one record per line, parsed with anchored patterns,
-- never executed as code):
--   slot   <monitor> <n>
--   view   <monitor> <tags>            tags = comma-separated integers
--   prev   <monitor> <tags>
--   focus  <monitor> <viewkey> <0xaddr>
--   layout <monitor> <slot> <layout> [orientation=<name>]
-- Monitor names are restricted to [A-Za-z0-9._-]; anything else is not persisted.
local STATE_MAX_BYTES = 64 * 1024
local STATE_MAX_LINES = 2000

local function safe_name(name)
  return type(name) == "string" and #name <= 64 and name:match("^[A-Za-z0-9._%-]+$") ~= nil
end

local function tags_to_string(set)
  return table.concat(sorted_keys(set), ",")
end

local function parse_tag_list(str)
  local out = {}
  if not str or str == "" then return out end
  for n in str:gmatch("(%d+)") do
    local k = tonumber(n)
    if k and k >= 1 and k <= 999 then out[k] = true end
  end
  return out
end

save_state = function()
  local lines = {}
  for _, name in ipairs(sorted_keys(slots)) do
    if safe_name(name) then lines[#lines + 1] = string.format("slot %s %d", name, slots[name]) end
  end
  for _, name in ipairs(sorted_keys(view)) do
    if safe_name(name) then lines[#lines + 1] = string.format("view %s %s", name, tags_to_string(view[name])) end
  end
  for _, name in ipairs(sorted_keys(prev)) do
    if safe_name(name) and prev[name] then
      lines[#lines + 1] = string.format("prev %s %s", name, tags_to_string(prev[name]))
    end
  end
  for _, name in ipairs(sorted_keys(lastfocus)) do
    if safe_name(name) then
      for _, key in ipairs(sorted_keys(lastfocus[name])) do
        local addr = tostring(lastfocus[name][key])
        if key:match("^[%d,]+$") and addr:match("^0x[0-9a-f]+$") then
          lines[#lines + 1] = string.format("focus %s %s %s", name, key, addr)
        end
      end
    end
  end
  for _, name in ipairs(sorted_keys(layouts)) do
    if safe_name(name) then
      for _, slot in ipairs(sorted_keys(layouts[name])) do
        local L = layouts[name][slot]
        if tostring(slot):match("^[%da-z]+$") and L.layout:match("^[a-z]+$") then
          local o = L.opts and L.opts.orientation
          lines[#lines + 1] = string.format("layout %s %s %s%s", name, slot, L.layout,
            (o and tostring(o):match("^[a-z]+$")) and (" orientation=" .. o) or "")
        end
      end
    end
  end
  local body = table.concat(lines, "\n") .. "\n"

  -- Exclusive-ish temporary with an unpredictable name in the destination directory, then
  -- rename over the target (rename replaces a planted symlink instead of writing through
  -- it). Lua has no O_EXCL, so this is same-user hardening, not a security boundary; the
  -- file holds no secrets.
  local path = cfg.state_dir .. "/state"
  local tmp = string.format("%s/.state.%d.%d.tmp", cfg.state_dir, os.time(), math.random(1, 1e9))
  local f = io.open(tmp, "w")
  if not f then
    os.execute("mkdir -p -m 700 '" .. cfg.state_dir:gsub("'", "'\\''") .. "'")
    f = io.open(tmp, "w")
    if not f then log("cannot write %s", tmp) return end
  end
  local ok = f:write(body)
  f:close()
  if not ok or not os.rename(tmp, path) then
    os.remove(tmp)
    log("state save failed")
  end
end

-- Returns { slots, view, prev, focus, layout } from the state file, or empty tables.
-- Bounded read, one anchored pattern per record type; unknown or malformed lines are
-- ignored rather than repaired.
local function load_state()
  local st = { slots = {}, view = {}, prev = {}, focus = {}, layout = {} }
  local f = io.open(cfg.state_dir .. "/state", "r")
  if not f then return st end
  local body = f:read(STATE_MAX_BYTES + 1)
  f:close()
  if not body or #body > STATE_MAX_BYTES then
    log("state file missing or oversized; ignoring")
    return st
  end
  local n = 0
  for line in body:gmatch("[^\n]+") do
    n = n + 1
    if n > STATE_MAX_LINES then break end
    local kind, rest = line:match("^(%a+) (.*)$")
    if kind == "slot" then
      local name, num = rest:match("^([A-Za-z0-9._%-]+) (%d+)$")
      if name and tonumber(num) < 100 then st.slots[name] = tonumber(num) end
    elseif kind == "view" or kind == "prev" then
      local name, tags = rest:match("^([A-Za-z0-9._%-]+) ([%d,]+)$")
      if name then st[kind][name] = parse_tag_list(tags) end
    elseif kind == "focus" then
      local name, key, addr = rest:match("^([A-Za-z0-9._%-]+) ([%d,]+) (0x[0-9a-f]+)$")
      if name then
        st.focus[name] = st.focus[name] or {}
        st.focus[name][key] = addr
      end
    elseif kind == "layout" then
      local name, slot, layout, orient = rest:match("^([A-Za-z0-9._%-]+) ([%da-z]+) ([a-z]+)%s*(.*)$")
      if name then
        local o = orient and orient:match("^orientation=([a-z]+)$") or nil
        st.layout[name] = st.layout[name] or {}
        st.layout[name][slot] = { layout = layout, opts = o and { orientation = o } or nil }
      end
    end
  end
  return st
end

-- ---------------------------------------------------------------------------------------
-- Window queries
-- ---------------------------------------------------------------------------------------

local function windows_on(wsid)
  local out = {}
  for _, w in ipairs(hl.get_windows({ workspace = wsid })) do
    if w.mapped and not w.pinned then out[#out + 1] = w end
  end
  return out
end

-- Windows on a monitor's pair that carry membership tags.
local function managed_windows(monname)
  local p = pairs_by_mon[monname]
  if not p then return {} end
  local out = {}
  for _, id in ipairs({ p.vis, p.hid }) do
    for _, w in ipairs(windows_on(id)) do
      if is_managed(w) then out[#out + 1] = w end
    end
  end
  return out
end

-- On-screen order: tiled before floating, then x then y (master first / stack top-down,
-- dwindle left-to-right top-to-bottom).
local function geometry_sorted(wins)
  local items = {}
  for _, w in ipairs(wins) do
    local at = w.at or {}
    items[#items + 1] = { w = w, f = w.floating and 1 or 0, x = at.x or at[1] or 0, y = at.y or at[2] or 0 }
  end
  table.sort(items, function(a, b)
    if a.f ~= b.f then return a.f < b.f end
    if math.abs(a.x - b.x) > 2 then return a.x < b.x end
    if math.abs(a.y - b.y) > 2 then return a.y < b.y end
    return tostring(a.w.address) < tostring(b.w.address)
  end)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.w end
  return out
end

-- Highest rank currently recorded for a tag on a monitor (0 if none).
local function max_rank(monname, k)
  local m = 0
  for _, w in ipairs(managed_windows(monname)) do
    local members, pos = read_tags(w)
    if members[k] then
      local r = pos[k] or 0
      if r > m then m = r end
    end
  end
  return m
end

-- ---------------------------------------------------------------------------------------
-- Rank snapshot
-- ---------------------------------------------------------------------------------------

-- Write ranks for every visible managed window on `monname`, for the given tag set
-- (normally the view being left). Only rewrites WMT_POS when it actually changes.
-- Geometry cannot see order in monocle (every tiled window has the same box), and Hyprland
-- exposes no list index, so a geometry snapshot there would collapse to address order and
-- discard any roll. What monocle needs preserved is only the cyclic order: re-showing
-- inserts lowest rank first and focus memory restores the window on top, so keeping the
-- ranks the windows already carry is exact. Unranked windows go after the ranked ones.
local current_layout -- defined with the layout helpers below

local function rank_sorted(wins, tagset)
  local items = {}
  for _, w in ipairs(wins) do
    local _, pos = read_tags(w)
    local best
    for k, r in pairs(pos) do if tagset[k] and (not best or r < best) then best = r end end
    items[#items + 1] = { w = w, r = best or 1e9 }
  end
  table.sort(items, function(a, b)
    if a.r ~= b.r then return a.r < b.r end
    return tostring(a.w.address) < tostring(b.w.address)
  end)
  local out = {}
  for i, it in ipairs(items) do out[i] = it.w end
  return out
end

local function snapshot_ranks(monname, tagset)
  local p = pairs_by_mon[monname]
  if not p then return end
  local visible = {}
  for _, w in ipairs(windows_on(p.vis)) do
    if is_managed(w) then visible[#visible + 1] = w end
  end
  local ordered
  if current_layout(monname) == "monocle" then
    ordered = rank_sorted(visible, tagset)
  else
    ordered = geometry_sorted(visible)
  end
  local counters = {}
  for _, w in ipairs(ordered) do
    local members, pos = read_tags(w)
    local changed = false
    for k in pairs(members) do
      if tagset[k] then
        counters[k] = (counters[k] or 0) + 1
        if pos[k] ~= counters[k] then
          pos[k] = counters[k]
          changed = true
        end
      end
    end
    if changed then write_tags(w, members, pos) end
  end
end

-- ---------------------------------------------------------------------------------------
-- Focus and reconcile
-- ---------------------------------------------------------------------------------------

local function fix_focus(monname, prefer)
  local p = pairs_by_mon[monname]
  if not p then return end
  local cands = windows_on(p.vis)
  local pick = nil
  if prefer then
    for _, w in ipairs(cands) do
      if w.address == prefer then pick = w break end
    end
  end
  local aw = hl.get_active_window()
  if aw and ws_id(aw) == p.vis then
    -- focus is already fine; only an explicit preference overrides it
    if pick and pick.address ~= aw.address then dispatch(hl.dsp.focus({ window = wsel(pick) })) end
    return
  end
  if not pick then
    for _, w in ipairs(cands) do
      if not pick or (w.focus_history_id or 1e9) < (pick.focus_history_id or 1e9) then pick = w end
    end
  end
  if pick then
    dispatch(hl.dsp.focus({ window = wsel(pick) }))
  else
    local m = monitor_by_name(monname)
    if m and m.active_workspace and m.active_workspace.id ~= p.vis then
      dispatch(hl.dsp.focus({ workspace = p.vis }))
    end
  end
end

local emit_all
local schedule_emit

local function view_key(set)
  return table.concat(sorted_keys(set), ",")
end

-- Re-resolve a window captured earlier; nil if it is gone.
local function alive(addr)
  if not addr then return nil end
  local ok, w = pcall(hl.get_window, "address:" .. tostring(addr))
  if ok and w and w.mapped then return w end
  return nil
end

-- ---- per-tag layouts ----------------------------------------------------------------

local function layout_equal(a, b)
  if not a or not b or a.layout ~= b.layout then return false end
  local ao, bo = a.opts or {}, b.opts or {}
  for k, v in pairs(ao) do if tostring(bo[k]) ~= tostring(v) then return false end end
  for k, v in pairs(bo) do if tostring(ao[k]) ~= tostring(v) then return false end end
  return true
end

local function layout_label(L)
  for _, e in ipairs(cfg.layouts) do
    if layout_equal(e, L) then return e.name or e.layout end
  end
  return L.layout
end

-- dwm pertag slot for a view: the lowest selected tag, except the all-tags view which has
-- a slot of its own. A combo therefore shows (and edits) its lowest tag's layout.
local function layout_key(set)
  if set_eq(set, all_tags()) then return "all" end
  return tostring(min_key(set) or 1)
end

-- What the visible workspace is running right now. Only the algorithm name is readable
-- (HL.Workspace.tiled_layout); options such as master orientation come from our record.
current_layout = function(monname)
  local p = pairs_by_mon[monname]
  local m = monitor_by_name(monname)
  local ws = m and m.active_workspace
  if not p or not ws or ws.id ~= p.vis then return nil end
  return ws.tiled_layout
end

-- Record the visible workspace's layout under the current view. If the algorithm still
-- matches what we recorded, keep the recorded options (orientation); if something else
-- changed it (Omarchy's own toggle), record the bare algorithm.
local function remember_layout(monname)
  -- A workspace rule changes the live layout asynchronously (verified: still the old
  -- algorithm right after the call, new one ~300 ms later). While one of ours is settling,
  -- the compositor's answer is transient; recording it would attach the wrong layout to
  -- the tag being left on a fast switch.
  if layout_settling[monname] then return end
  local cur = current_layout(monname)
  if not cur then return end
  layouts[monname] = layouts[monname] or {}
  local key = layout_key(view[monname])
  local rec = layouts[monname][key]
  if not rec or rec.layout ~= cur then
    layouts[monname][key] = { layout = cur }
  end
end

-- Apply a layout record to the monitor's visible workspace via the same workspace rule
-- Omarchy's toggle uses; it takes effect on the live workspace.
local function apply_layout(monname, L)
  local p = pairs_by_mon[monname]
  if not p or not L then return end
  local spec = { workspace = tostring(p.vis), layout = L.layout }
  if L.opts and next(L.opts) then spec.layout_opts = L.opts end
  local ok, err = pcall(hl.workspace_rule, spec)
  if not ok then log("workspace_rule for layout failed: %s", tostring(err)) return end
  layout_settling[monname] = true
  -- Master orientation only re-arranges on a live layoutmsg, which must reach the master
  -- algorithm: sent too early it hits the outgoing layout ("unknown dwindle layout
  -- message"). Wait for the rule to land, check, then nudge the focused monitor only.
  local o = L.opts and L.opts.orientation
  hl.timer(guard("layout nudge", function()
    layout_settling[monname] = nil
    if L.layout == "master" and o and active_monname() == monname and current_layout(monname) == "master" then
      dispatch(hl.dsp.layout("orientation" .. tostring(o)))
    end
  end), { timeout = 400, type = "oneshot" })
end

local function apply_view_layout(monname)
  local rec = layouts[monname] and layouts[monname][layout_key(view[monname])]
  if rec then apply_layout(monname, rec) end
end

-- Seed from Omarchy's per-workspace files: workspace n's rule becomes tag n's layout,
-- for tags that have no record yet.
local function seed_layouts_from_omarchy(monname)
  layouts[monname] = layouts[monname] or {}
  for n = 1, cfg.ntags do
    local key = tostring(n)
    if not layouts[monname][key] then
      local f = io.open(cfg.omarchy_layouts_dir .. "/" .. n .. ".lua", "r")
      if f then
        local text = f:read("*a") or ""
        f:close()
        local layout = text:match('layout%s*=%s*"([%w_]+)"')
        if layout then
          local rec = { layout = layout }
          local orient = text:match('orientation%s*=%s*"([%w_]+)"')
          if orient then rec.opts = { orientation = orient } end
          layouts[monname][key] = rec
        end
      end
    end
  end
end

-- Remember which window to come back to for the current view of a monitor.
local function remember_focus(monname)
  local p = pairs_by_mon[monname]
  if not p then return end
  local aw = hl.get_active_window()
  if not aw or ws_id(aw) ~= p.vis then return end
  lastfocus[monname] = lastfocus[monname] or {}
  lastfocus[monname][view_key(view[monname])] = aw.address
end

local reconcile -- forward

-- Deferred reconcile, coalesced per monitor: a burst of events queues one run.
local function later(ms, fn)
  hl.timer(guard("timer", fn), { timeout = ms, type = "oneshot" })
end

local function schedule_reconcile(monname, opts)
  if pending[monname] then return end
  pending[monname] = true
  later(1, function()
    pending[monname] = nil
    reconcile(monname, opts or {})
  end)
end

-- opts: { old_view = set | nil, prefer = address | nil, focus = bool }
reconcile = function(monname, opts, depth)
  opts = opts or {}
  depth = depth or 0
  if busy then dirty[monname] = true return end
  local p = pairs_by_mon[monname]
  if not p then return end
  local V = view[monname] or { [1] = true }
  busy = true
  local ok, err = pcall(function()
    if opts.old_view then snapshot_ranks(monname, opts.old_view) end

    local hide, show = {}, {}
    for _, w in ipairs(managed_windows(monname)) do
      local members, pos = read_tags(w)
      local should = intersects(members, V)
      local id = ws_id(w)
      if not should and id == p.vis then
        hide[#hide + 1] = w
      elseif should and id == p.hid then
        local mk = nil
        for k in pairs(members) do
          if V[k] and (not mk or k < mk) then mk = k end
        end
        show[#show + 1] = { w = w, k = mk or 1e9, r = (mk and pos[mk]) or 1e9 }
      end
    end

    for _, w in ipairs(hide) do
      local f = w.fullscreen
      if f and f ~= 0 then fs_state[w.address] = f end
      dispatch(hl.dsp.window.move({ workspace = p.hid, follow = false, window = wsel(w) }))
    end

    table.sort(show, function(a, b)
      if a.k ~= b.k then return a.k < b.k end
      if a.r ~= b.r then return a.r < b.r end
      return tostring(a.w.address) < tostring(b.w.address)
    end)
    for _, it in ipairs(show) do
      dispatch(hl.dsp.window.move({ workspace = p.vis, follow = false, window = wsel(it.w) }))
      -- chain focus so dwindle inserts the next one relative to this one
      dispatch(hl.dsp.focus({ window = wsel(it.w) }))
    end
    for _, it in ipairs(show) do
      local f = fs_state[it.w.address]
      if f then
        fs_state[it.w.address] = nil
        local mode = (f == 2) and "maximized" or "fullscreen"
        dispatch(hl.dsp.window.fullscreen({ mode = mode, window = wsel(it.w) }))
      end
    end

    if opts.focus ~= false then fix_focus(monname, opts.prefer) end
  end)
  busy = false
  if not ok then log("reconcile(%s) failed: %s", monname, tostring(err)) end
  if dirty[monname] and depth < 3 then
    dirty[monname] = nil
    reconcile(monname, { focus = opts.focus }, depth + 1)
  end
  dirty[monname] = nil
  schedule_emit()
end

-- ---------------------------------------------------------------------------------------
-- Bar IPC
-- ---------------------------------------------------------------------------------------

local function emit_line(monname)
  local p = pairs_by_mon[monname]
  if not p then return nil end
  local occ, urg, foc = {}, {}, {}
  local aw = hl.get_active_window()
  for _, w in ipairs(managed_windows(monname)) do
    local members = read_tags(w)
    for k in pairs(members) do
      occ[k] = (occ[k] or 0) + 1
      if urgent[w.address] then urg[k] = true end
      if aw and aw.address == w.address then foc[k] = true end
    end
  end
  local v = table.concat(sorted_keys(view[monname] or {}), ",")
  local o = {}
  for _, k in ipairs(sorted_keys(occ)) do o[#o + 1] = k .. ":" .. occ[k] end
  return string.format("hyprtags>>%s|v=%s|o=%s|u=%s|f=%s", monname, v, table.concat(o, ","),
    table.concat(sorted_keys(urg), ","), table.concat(sorted_keys(foc), ","))
end

local adopt_strays_ref -- set once adopt_strays is defined (it lives further down)

emit_all = function()
  if adopt_strays_ref then adopt_strays_ref() end
  for _, m in ipairs(hl.get_monitors()) do
    local line = emit_line(m.name)
    if line then dispatch(hl.dsp.event(line)) end
  end
end

schedule_emit = function()
  if emit_timer then return end
  emit_timer = hl.timer(function()
    emit_timer = nil
    local ok, err = pcall(emit_all)
    if not ok then log("emit failed: %s", tostring(err)) end
  end, { timeout = cfg.emit_delay, type = "oneshot" })
end

-- ---------------------------------------------------------------------------------------
-- Operations
-- ---------------------------------------------------------------------------------------

local function resolve_mon(monname)
  if monname and pairs_by_mon[monname] then return monname end
  local a = active_monname()
  if a and pairs_by_mon[a] then return a end
  return nil
end

local function set_view(monname, newset, opts)
  monname = resolve_mon(monname)
  if not monname or set_empty(newset) then return end
  local cur = view[monname]
  if set_eq(cur, newset) then
    -- still make sure the monitor is on its visible workspace
    fix_focus(monname)
    schedule_emit()
    return
  end
  remember_focus(monname)
  remember_layout(monname)
  prev[monname] = set_copy(cur)
  view[monname] = set_copy(newset)
  local remembered = lastfocus[monname] and lastfocus[monname][view_key(newset)]
  apply_view_layout(monname)
  save_state()
  reconcile(monname, { old_view = cur, prefer = (opts and opts.prefer) or remembered })
end

local function assign_tags(w, members, monname)
  monname = monname or monname_of(w)
  local cur, pos = read_tags(w)
  local newpos = {}
  for k in pairs(members) do
    if cur[k] and pos[k] then
      newpos[k] = pos[k]
    else
      newpos[k] = (monname and max_rank(monname, k) or 0) + 1
    end
  end
  write_tags(w, members, newpos)
end

-- Focused window as the target of a tag operation. Scratchpad (special) windows are
-- allowed: tagging one pulls it out into the pair. Pinned windows are sticky, skip them.
local function target_window(w)
  if w then return w end
  local aw = hl.get_active_window()
  if not aw or aw.pinned then return nil end
  return aw
end

-- After tagging a window that sits on a special workspace, move it into the pair:
-- on screen if one of its tags is viewed, else parked hidden. Returns the address to
-- prefer for focus, or nil.
local function pull_from_special(w, monname)
  if not is_special(w) then return nil end
  local p = monname and pairs_by_mon[monname]
  if not p then return nil end
  local members = read_tags(w)
  local visible = intersects(members, view[monname])
  dispatch(hl.dsp.window.move({ workspace = visible and p.vis or p.hid, follow = false, window = wsel(w) }))
  return visible and w.address or nil
end

local function next_focus_after(w)
  local monname = monname_of(w)
  local p = monname and pairs_by_mon[monname]
  if not p then return nil end
  local best
  for _, o in ipairs(windows_on(p.vis)) do
    if o.address ~= w.address then
      if not best or (o.focus_history_id or 1e9) < (best.focus_history_id or 1e9) then best = o end
    end
  end
  return best and best.address or nil
end

function M.view(tags, monname)
  local s = type(tags) == "table" and set_of(tags) or { [tonumber(tags)] = true }
  set_view(monname, s)
end

function M.toggleview(k, monname)
  monname = resolve_mon(monname)
  if not monname then return end
  k = tonumber(k)
  local s = set_copy(view[monname])
  if s[k] then s[k] = nil else s[k] = true end
  if set_empty(s) then return end
  set_view(monname, s)
end

-- dwm SUPER+0: view everything; pressed again, go back to where you were.
-- Next/previous tag among the occupied ones (plus the current view), wrapping. This is
-- Omarchy's "next/previous existing workspace" translated to tags.
function M.view_next(dir, monname)
  monname = resolve_mon(monname)
  if not monname then return end
  local occ = {}
  for _, w in ipairs(managed_windows(monname)) do
    for k in pairs((read_tags(w))) do occ[k] = true end
  end
  local cur = min_key(view[monname]) or 1
  occ[cur] = true
  local ks = sorted_keys(occ)
  if #ks < 2 then return end
  local idx = 1
  for i, k in ipairs(ks) do if k == cur then idx = i end end
  local nk = ks[((idx - 1 + dir) % #ks) + 1]
  set_view(monname, { [nk] = true })
end

function M.view_all(monname)
  monname = resolve_mon(monname)
  if not monname then return end
  if set_eq(view[monname], all_tags()) then
    M.view_previous(monname)
  else
    set_view(monname, all_tags())
  end
end

function M.view_previous(monname)
  monname = resolve_mon(monname)
  if not monname or not prev[monname] then return end
  set_view(monname, prev[monname])
end

function M.tag(tags, w, monname)
  w = target_window(w)
  if not w then return end
  local s = type(tags) == "table" and set_of(tags) or { [tonumber(tags)] = true }
  if set_empty(s) then return end
  monname = monname_of(w) or resolve_mon(monname)
  assign_tags(w, s, monname)
  local prefer = pull_from_special(w, monname) or next_focus_after(w)
  if monname then reconcile(monname, { prefer = prefer }) end
end

function M.toggletag(k, w, monname)
  w = target_window(w)
  if not w then return end
  k = tonumber(k)
  local members = read_tags(w)
  if members[k] then
    members[k] = nil
    if set_empty(members) then return end -- refuse to strip the last tag
  else
    members[k] = true
  end
  monname = monname_of(w) or resolve_mon(monname)
  assign_tags(w, members, monname)
  local prefer = pull_from_special(w, monname) or next_focus_after(w)
  if monname then reconcile(monname, { prefer = prefer }) end
end

function M.tag_all(w) M.tag(sorted_keys(all_tags()), w) end

function M.winview()
  local aw = hl.get_active_window()
  if not aw then return end
  local members = read_tags(aw)
  if set_empty(members) then return end
  set_view(monname_of(aw), members)
end

function M.focusurgent()
  local w = hl.get_urgent_window()
  if not w then
    for a in pairs(urgent) do
      w = hl.get_window("address:" .. a)
      if w then break end
    end
  end
  if not w then return end
  local monname = monname_of(w)
  local p = monname and pairs_by_mon[monname]
  if p and ws_id(w) == p.hid then
    local members = read_tags(w)
    local k = min_key(members)
    if k then set_view(monname, { [k] = true }, { prefer = w.address }) end
  end
  dispatch(hl.dsp.focus({ window = wsel(w) }))
end

function M.sticky()
  dispatch(hl.dsp.window.pin())
end

-- Shift the focused window's tags and the view by `dir` (wraps), dwm shiftboth.
local function shift_set(s, dir)
  local out = {}
  for k in pairs(s) do
    local nk = ((k - 1 + dir) % cfg.ntags) + 1
    out[nk] = true
  end
  return out
end

function M.shiftboth(dir)
  local aw = target_window(nil)
  local monname = aw and monname_of(aw) or resolve_mon(nil)
  if not monname then return end
  if aw and is_managed(aw) then
    local members = read_tags(aw)
    assign_tags(aw, shift_set(members, dir), monname)
  end
  set_view(monname, shift_set(view[monname], dir), { prefer = aw and aw.address })
end

function M.shiftview(dir)
  local monname = resolve_mon(nil)
  if not monname then return end
  set_view(monname, shift_set(view[monname], dir))
end

-- Send focused window to the next/previous monitor; it takes that monitor's view.
function M.tagmon(dir)
  local aw = target_window(nil)
  if not aw then return end
  local ms = monitors_sorted()
  if #ms < 2 then return end
  local src = monname_of(aw)
  local idx = 1
  for i, m in ipairs(ms) do if m.name == src then idx = i end end
  local target = ms[((idx - 1 + dir) % #ms) + 1].name
  local p = ensure_pair(target)
  assign_tags(aw, set_copy(view[target]), target)
  dispatch(hl.dsp.window.move({ workspace = p.vis, follow = false, window = wsel(aw) }))
  if src then reconcile(src, {}) end
  reconcile(target, { focus = false })
end

-- Set the current view's layout: set_layout("master", { orientation = "center" }).
function M.set_layout(layout, opts, monname)
  monname = resolve_mon(monname)
  if not monname or not layout then return end
  layouts[monname] = layouts[monname] or {}
  local slot = layout_key(view[monname])
  local old = layouts[monname][slot]
  local rec = { layout = layout, opts = opts }
  if old and not layout_equal(old, rec) then
    prev_layout[monname] = prev_layout[monname] or {}
    prev_layout[monname][slot] = old
  end
  layouts[monname][slot] = rec
  apply_layout(monname, rec)
  save_state()
  -- label comes from cfg.layouts (config, not data); still restrict to a safe charset
  local label = tostring(layout_label(rec)):gsub("[^%w %-]", "")
  hl.exec_cmd("/usr/bin/omarchy-notification-send -g 󱂬 'Layout: " .. label .. "'")
end

-- Walk cfg.layouts forwards or backwards from the current view's layout.
function M.cycle_layout(dir, monname)
  monname = resolve_mon(monname)
  if not monname then return end
  dir = dir or 1
  local key = layout_key(view[monname])
  local rec = layouts[monname] and layouts[monname][key]
  local cur = current_layout(monname)
  if not rec or (cur and rec.layout ~= cur) then rec = { layout = cur or "dwindle" } end
  local idx = 1
  for i, e in ipairs(cfg.layouts) do if layout_equal(e, rec) then idx = i end end
  if not layout_equal(cfg.layouts[idx], rec) then
    -- bare algorithm with unknown options: match on the name
    for i, e in ipairs(cfg.layouts) do if e.layout == rec.layout then idx = i break end end
  end
  local n = #cfg.layouts
  local nxt = cfg.layouts[((idx - 1 + dir) % n) + 1]
  M.set_layout(nxt.layout, nxt.opts, monname)
end

-- dwm setlayout({0}): flip between this slot's current and previous layout.
function M.toggle_layout(monname)
  monname = resolve_mon(monname)
  if not monname then return end
  local slot = layout_key(view[monname])
  local p = prev_layout[monname] and prev_layout[monname][slot]
  if not p then M.cycle_layout(1, monname) return end
  M.set_layout(p.layout, p.opts, monname)
end

local ORIENTATIONS = { "left", "top", "right", "bottom", "center" }

local function master_orientation(monname)
  local rec = layouts[monname] and layouts[monname][layout_key(view[monname])]
  if rec and rec.layout == "master" then return (rec.opts and rec.opts.orientation) or "left" end
  return nil
end

-- dwm rotatelayoutaxis: turn the master area around (left → top → right → bottom → center).
-- Only meaningful on a master slot; other layouts are left alone.
function M.rotate_layout_axis(dir, monname)
  monname = resolve_mon(monname)
  local o = monname and master_orientation(monname)
  if not o then return end
  local idx = 1
  for i, v in ipairs(ORIENTATIONS) do if v == o then idx = i end end
  local n = #ORIENTATIONS
  M.set_layout("master", { orientation = ORIENTATIONS[((idx - 1 + (dir or 1)) % n) + 1] }, monname)
end

-- dwm mirrorlayout: swap master and stack sides.
function M.mirror_layout(monname)
  monname = resolve_mon(monname)
  local o = monname and master_orientation(monname)
  if not o then return end
  local mirror = { left = "right", right = "left", top = "bottom", bottom = "top", center = "center" }
  M.set_layout("master", { orientation = mirror[o] }, monname)
end

-- dwm togglegaps: zero the gaps, restore them on the next call.
function M.toggle_gaps()
  if gaps_saved then
    hl.config({ general = { gaps_in = gaps_saved[1], gaps_out = gaps_saved[2] } })
    gaps_saved = nil
  else
    local gi = hl.get_config("general.gaps_in")
    local go = hl.get_config("general.gaps_out")
    gaps_saved = { gi, go }
    hl.config({ general = { gaps_in = 0, gaps_out = 0 } })
  end
end

function M.emit() emit_all() end

function M.relayout(monname)
  monname = resolve_mon(monname)
  if monname then snapshot_ranks(monname, view[monname]) end
  schedule_emit()
end

function M.debug()
  local lines = {}
  lines[#lines + 1] = "monitors:"
  for name, p in pairs(pairs_by_mon) do
    lines[#lines + 1] = string.format("  %s vis=%d hid=%d view={%s} prev={%s}", name, p.vis, p.hid,
      table.concat(sorted_keys(view[name] or {}), ","), table.concat(sorted_keys(prev[name] or {}), ","))
  end
  lines[#lines + 1] = "windows:"
  for _, w in ipairs(hl.get_windows()) do
    local members, pos = read_tags(w)
    lines[#lines + 1] = string.format("  %s ws=%s class=%s tags={%s} pos=%s urgent=%s", tostring(w.address),
      tostring(ws_id(w)), tostring(w.class), table.concat(sorted_keys(members), ","), pos_string(pos) or "-",
      tostring(urgent[w.address] or false))
  end
  lines[#lines + 1] = "layouts:"
  for name, tbl in pairs(layouts) do
    for key, rec in pairs(tbl) do lines[#lines + 1] = string.format("  %s tag %s -> %s", name, key, layout_label(rec)) end
  end
  lines[#lines + 1] = "focus memory:"
  for name, tbl in pairs(lastfocus) do
    for key, addr in pairs(tbl) do lines[#lines + 1] = string.format("  %s view={%s} -> %s", name, key, addr) end
  end
  if #bind_failures > 0 then
    lines[#lines + 1] = "bind failures:"
    for _, f in ipairs(bind_failures) do lines[#lines + 1] = "  " .. f end
  end
  lines[#lines + 1] = "log:"
  for _, l in ipairs(log_lines) do lines[#lines + 1] = "  " .. l end
  local f = io.open(cfg.state_dir .. "/debug.txt", "w")
  if f then f:write(table.concat(lines, "\n"), "\n") f:close() end
  -- (same-user diagnostic file; contains window classes and addresses, no secrets)
  return table.concat(lines, "\n")
end

-- Undo: every managed window back onto workspace 1, tags stripped. For uninstalling.
function M.uninstall()
  for _, w in ipairs(hl.get_windows()) do
    local members, _, posraw = read_tags(w)
    if not set_empty(members) then
      for k in pairs(members) do tag_op(w, "-WMT" .. k) end
      if posraw then tag_op(w, "-" .. posraw) end
      if not is_special(w) then
        dispatch(hl.dsp.window.move({ workspace = 1, follow = false, window = wsel(w) }))
      end
    end
  end
  dispatch(hl.dsp.focus({ workspace = 1 }))
end

-- ---------------------------------------------------------------------------------------
-- Adoption of windows that are not (yet) managed
-- ---------------------------------------------------------------------------------------

local function legacy_tag_for(wsid)
  if wsid >= 1 and wsid <= cfg.ntags then return wsid end
  return nil
end

-- Bring one window under management according to where it sits. `default_set` is what
-- an untagged window on the pair gets (the current view for a freshly opened window,
-- cfg.stray_tag for anything found lying around). Returns the monitor name that needs a
-- reconcile, or nil.
local function adopt(w, default_set)
  if not w.mapped or w.pinned or is_special(w) then return nil end
  if is_managed(w) then return nil end
  local id = ws_id(w)
  if not id then return nil end
  local monname = mon_of_ws[id]
  if monname then
    local tags = default_set and set_copy(default_set) or { [cfg.stray_tag] = true }
    if set_empty(tags) then tags = { [cfg.stray_tag] = true } end
    assign_tags(w, tags, monname)
    return monname
  end
  local m = w.monitor
  monname = m and m.name or active_monname()
  if not monname then return nil end
  local p = ensure_pair(monname)
  -- a numbered workspace 1..ntags means "that tag"; anything else gets the stray tag
  local k = legacy_tag_for(id) or cfg.stray_tag
  assign_tags(w, { [k] = true }, monname)
  local dest = view[monname][k] and p.vis or p.hid
  dispatch(hl.dsp.window.move({ workspace = dest, follow = false, window = wsel(w) }))
  return monname
end

-- Safety net: every mapped, unpinned window outside the scratchpad must carry a tag.
-- Runs after every emit and on a timer, so a window that slipped past window.open (or was
-- stripped by hand) can never stay stuck on a workspace the keys cannot reach.
local function adopt_strays()
  if busy then return end
  local touched = {}
  for _, w in ipairs(hl.get_windows()) do
    local mn = adopt(w, nil)
    if mn then touched[mn] = true end
  end
  for mn in pairs(touched) do reconcile(mn, { focus = false }) end
end

adopt_strays_ref = adopt_strays

-- ---------------------------------------------------------------------------------------
-- Key helpers (the engine binds nothing itself; a keys module does, see cfg.keys)
-- ---------------------------------------------------------------------------------------

local function combo_reset()
  combo.active = false
  if combo.timer then
    pcall(function() combo.timer:set_enabled(false) end)
    combo.timer = nil
  end
end

local function combo_touch()
  combo.active = true
  if combo.timer then pcall(function() combo.timer:set_enabled(false) end) end
  combo.timer = hl.timer(function()
    combo.timer = nil
    combo.active = false
  end, { timeout = cfg.combo_timeout, type = "oneshot" })
end

-- dwm COMBO patch: while the modifier stays held, successive tag keys OR together.
function M.comboview(k)
  local monname = resolve_mon(nil)
  if not monname then return end
  if combo.active then
    local s = set_copy(view[monname])
    s[k] = true
    set_view(monname, s)
  else
    set_view(monname, { [k] = true })
  end
  combo_touch()
end

function M.combotag(k)
  local w = target_window(nil)
  if not w then return end
  local members = read_tags(w)
  if combo.active and not set_empty(members) then
    members[k] = true
    M.tag(sorted_keys(members), w)
  else
    M.tag(k, w)
  end
  combo_touch()
end

-- Release binds on the modifier keys end a combo; the timer above is the fallback.
function M.combo_enable(mod)
  mod = mod or "SUPER"
  for _, key in ipairs({ "Super_L", "Super_R" }) do
    pcall(hl.bind, mod .. " + " .. key, combo_reset, { release = true, description = "hyprtags combo reset" })
  end
end

-- Bind one chord to a Lua function; a failure is logged and counted, never fatal, so a
-- broken bind cannot take the rest of the keyboard with it.
function M.bind(keys, fn, desc, opts)
  if not keys then return end
  opts = opts or {}
  opts.description = desc
  local ok, err = pcall(hl.bind, keys, guard(desc, fn), opts)
  if not ok then
    bind_failures[#bind_failures + 1] = keys .. ": " .. tostring(err)
    log("bind %s failed: %s", keys, tostring(err))
  end
end

function M.unbind(keys)
  pcall(hl.unbind, keys)
end

-- Replace whatever is on a chord with ours, as one step per chord. Every bind on a key
-- fires, so the unbind has to come first; if the bind then fails, only that chord is lost
-- and it is reported.
function M.rebind(keys, fn, desc, opts)
  M.unbind(keys)
  M.bind(keys, fn, desc, opts)
end

local function load_keys()
  bind_failures = {}
  if not cfg.keys then return end
  package.loaded[cfg.keys] = nil
  local ok, err = pcall(require, cfg.keys)
  if not ok then
    log("keys module %s failed: %s", tostring(cfg.keys), tostring(err))
    notify("keys module " .. tostring(cfg.keys) .. " failed: " .. tostring(err))
  end
  if #bind_failures > 0 then
    notify(#bind_failures .. " keybind(s) failed, see debug(): " .. bind_failures[1])
  end
end
-- ---------------------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------------------

local function setup_events()
  hl.on("window.open", guard("window.open", function(w)
    if busy then return end
    local wm = monname_of(w)
    local monname = adopt(w, wm and view[wm] or nil)
    if monname then reconcile(monname, {}) else schedule_emit() end
  end))

  -- On destroy the object is already expired and its address reads as nil.
  local function forget(w)
    local ok, addr = pcall(function() return w and w.address end)
    if ok and addr then
      urgent[addr] = nil
      fs_state[addr] = nil
    end
    schedule_emit()
  end
  hl.on("window.close", guard("window.close", forget))
  hl.on("window.destroy", guard("window.destroy", forget))

  hl.on("window.active", guard("window.active", function(w)
    -- the object can already be expired (address reads nil) when focus moves off a
    -- closing window; treat that as "nothing to record"
    local ok, addr = pcall(function() return w and w.address end)
    if ok and addr then
      urgent[addr] = nil
      if not busy then
        local mn = monname_of(w)
        if mn then remember_focus(mn) end
      end
    end
    schedule_emit()
  end))

  hl.on("window.urgent", guard("window.urgent", function(w)
    if w then urgent[w.address] = true end
    schedule_emit()
  end))

  hl.on("window.move_to_workspace", guard("window.move_to_workspace", function(w, ws)
    if busy or not w or not ws then return end
    if ws.special or ws.id < 0 then schedule_emit() return end
    local id = ws.id
    local monname = mon_of_ws[id]
    if monname then
      if is_managed(w) then
        local members = read_tags(w)
        local p = pairs_by_mon[monname]
        local should = intersects(members, view[monname])
        local src = nil
        -- came from another monitor's pair? retag with this monitor's view (dwm sendmon)
        local wm = w.monitor
        if wm and wm.name ~= monname and pairs_by_mon[wm.name] then src = wm.name end
        if src or (id == p.vis and not should) or (id == p.hid and should) then
          if src then assign_tags(w, set_copy(view[monname]), monname) end
          schedule_reconcile(monname)
        else
          schedule_emit()
        end
      else
        local addr = w.address
        later(1, function()
          local ww = alive(addr)
          if not ww then return end
          local mn = adopt(ww, view[monname])
          if mn then reconcile(mn, {}) end
        end)
      end
      return
    end
    if legacy_tag_for(id) then
      local addr = w.address
      local wm = w.monitor
      local mn0 = wm and wm.name or nil
      later(1, function()
        local ww = alive(addr)
        if not ww then return end
        local k = legacy_tag_for(id)
        local mn = mn0 or active_monname()
        if not mn then return end
        local p = ensure_pair(mn)
        assign_tags(ww, { [k] = true }, mn)
        local dest = view[mn][k] and p.vis or p.hid
        dispatch(hl.dsp.window.move({ workspace = dest, follow = false, window = wsel(ww) }))
        reconcile(mn, {})
      end)
    end
  end))

  hl.on("workspace.active", guard("workspace.active", function(ws)
    if busy or not ws then return end
    local id = ws.id
    local monname = mon_of_ws[id]
    if monname then
      local p = pairs_by_mon[monname]
      if id == p.hid then
        later(1, function()
          local aw = hl.get_active_window()
          if aw and ws_id(aw) == p.hid and is_managed(aw) then
            local k = min_key((read_tags(aw)))
            set_view(monname, { [k] = true }, { prefer = aw.address })
          else
            dispatch(hl.dsp.focus({ workspace = p.vis }))
          end
        end)
      else
        schedule_emit()
      end
      return
    end
    if id > 0 and legacy_tag_for(id) then
      local wsm = ws.monitor
      local mn0 = wsm and wsm.name or nil
      later(1, function()
        local k = legacy_tag_for(id)
        local mn = mn0 or active_monname()
        if not mn then return end
        ensure_pair(mn)
        for _, w in ipairs(windows_on(id)) do adopt(w, nil) end
        set_view(mn, { [k] = true })
        local p = pairs_by_mon[mn]
        dispatch(hl.dsp.focus({ workspace = p.vis }))
      end)
    end
  end))

  -- Omarchy's default/hypr/workspace-layouts.lua re-applies its per-workspace rules after
  -- our module ran; put the current view's layout back once the reload is complete.
  hl.on("config.reloaded", guard("config.reloaded", function()
    for name in pairs(pairs_by_mon) do apply_view_layout(name) end
  end))

  hl.on("monitor.added", guard("monitor.added", function(m)
    if not m then return end
    local name = m.name
    later(50, function()
      local p = ensure_pair(name)
      for _, w in ipairs(hl.get_windows({ monitor = name })) do adopt(w, nil) end
      reconcile(name, {})
      local mm = monitor_by_name(name)
      if mm and mm.active_workspace and mm.active_workspace.id ~= p.vis then
        dispatch(hl.dsp.focus({ workspace = p.vis }))
      end
    end)
  end))

  hl.on("monitor.removed", guard("monitor.removed", function(m)
    local name = m and m.name or nil
    later(50, function()
      local survivor = active_monname()
      if not survivor or survivor == name then
        local ms = hl.get_monitors()
        survivor = ms[1] and ms[1].name or nil
      end
      if not survivor then return end
      local sp = ensure_pair(survivor)
      local dead = name and pairs_by_mon[name]
      if dead then
        for _, id in ipairs({ dead.vis, dead.hid }) do
          for _, w in ipairs(windows_on(id)) do
            dispatch(hl.dsp.window.move({ workspace = sp.hid, follow = false, window = wsel(w) }))
          end
        end
        pairs_by_mon[name] = nil
        mon_of_ws[dead.vis] = nil
        mon_of_ws[dead.hid] = nil
      end
      reconcile(survivor, {})
    end)
  end))

  -- A pair workspace dragged to another monitor (Omarchy's SUPER+SHIFT+ALT+arrows) is
  -- sent home. Guarded: one attempt per workspace per second, and if the attempt does not
  -- actually move it back (the `workspace` key on this dispatcher is unverified on 0.56.2)
  -- the feature switches itself off rather than ping-pong the active workspace.
  hl.on("workspace.move_to_monitor", guard("workspace.move_to_monitor", function(ws, m)
    if busy or bounce_disabled or not ws or not m then return end
    local owner = mon_of_ws[ws.id]
    if not owner or owner == m.name then return end
    local id = ws.id
    if bounce_block[id] then return end
    bounce_block[id] = true
    later(1000, function() bounce_block[id] = nil end)
    later(1, function()
      dispatch(hl.dsp.workspace.move({ workspace = id, monitor = owner }))
      later(50, function()
        local wsn = hl.get_workspace(id)
        local now = wsn and wsn.monitor and wsn.monitor.name or nil
        if now ~= owner then
          bounce_disabled = true
          log("workspace %d did not return to %s (on %s); bounce disabled", id, owner, tostring(now))
          notify("cannot send workspace " .. id .. " back to " .. owner .. "; leaving it")
        end
      end)
    end)
  end))
end

-- ---------------------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------------------

local function derive_view(monname)
  local p = pairs_by_mon[monname]
  local s = {}
  for _, w in ipairs(windows_on(p.vis)) do
    for k in pairs((read_tags(w))) do s[k] = true end
  end
  return s
end

local function view_consistent(monname, V)
  local p = pairs_by_mon[monname]
  for _, w in ipairs(windows_on(p.vis)) do
    local members = read_tags(w)
    if not set_empty(members) and not intersects(members, V) then return false end
  end
  for _, w in ipairs(windows_on(p.hid)) do
    local members = read_tags(w)
    if not set_empty(members) and intersects(members, V) then return false end
  end
  return true
end

local function init()
  local st = load_state()
  slots = st.slots or {}
  local saved_view = st.view or {}
  local saved_prev = st.prev or {}
  layouts = {}
  for name, tbl in pairs(st.layout or {}) do
    layouts[name] = {}
    for key, rec in pairs(tbl) do
      if type(rec) == "table" and rec.layout then layouts[name][key] = rec end
    end
  end
  lastfocus = {}
  for name, tbl in pairs(st.focus or {}) do
    for key, addr in pairs(tbl) do
      if alive(addr) then
        lastfocus[name] = lastfocus[name] or {}
        lastfocus[name][key] = addr
      end
    end
  end

  -- rules for every monitor we have ever seen, so a replugged one lands on its pair
  for name in pairs(slots) do
    local vis, hid = pair_ids(slots[name])
    register_rules(name, vis, hid)
  end

  local monitors = hl.get_monitors()
  for _, m in ipairs(monitors) do
    local name = m.name
    local saved = saved_view[name]
    ensure_pair(name)
    prev[name] = saved_prev[name]

    local V = saved
    if not V or set_empty(V) or not view_consistent(name, V) then
      V = derive_view(name)
      if set_empty(V) then
        -- fresh install: keep whatever legacy workspace is on screen as the first tag
        local aws = m.active_workspace
        local k = aws and legacy_tag_for(aws.id) or nil
        V = { [k or 1] = true }
      end
    end
    view[name] = V
  end

  for _, m in ipairs(monitors) do
    for _, w in ipairs(hl.get_windows({ monitor = m.name })) do adopt(w, nil) end
  end

  setup_events()
  load_keys()

  for _, m in ipairs(monitors) do
    seed_layouts_from_omarchy(m.name)
    apply_view_layout(m.name)
    reconcile(m.name, { focus = false })
    local p = pairs_by_mon[m.name]
    local mm = monitor_by_name(m.name)
    if mm and mm.active_workspace then
      local id = mm.active_workspace.id
      if id ~= p.vis and id > 0 then dispatch(hl.dsp.focus({ workspace = p.vis })) end
    end
  end
  save_state()
  schedule_emit()
  if cfg.stray_sweep and cfg.stray_sweep > 0 then
    hl.timer(guard("stray sweep", adopt_strays), { timeout = cfg.stray_sweep, type = "repeat" })
  end
  log("init done: %d monitor(s)", #monitors)
end

function M.setup(opts)
  opts = opts or {}
  for k, v in pairs(opts) do cfg[k] = v end
  local ok, err = pcall(init)
  if not ok then
    log("init failed: %s", tostring(err))
    notify("init failed: " .. tostring(err))
  end
  return M
end

M.cfg = cfg
return M
