--[[
  ModMenu.core.persist: autosave of the menu state under the reserved store key __modmenu.

  Init({ autosave = true }) turns it on. The snapshot holds the dock edge, the active tab, the
  collapse state of collapsible sections and of folds, the values of value-bearing items, and the
  keys of values the player cleared. It keeps the saved part of any section not registered this
  session. It is written with store.Set("__modmenu", snapshot), so the host's other keys stay as they are.

  This module takes plain tables shaped like the shell's state and requires no shell module and
  no UE4SS global, so the no-game specs can load it.
]]

local Util = require("ModMenu.core.util")

local M = {}

--- The store key that holds the snapshot. Hosts must not use it for their own data.
M.KEY = "__modmenu"

--- The debounce, in milliseconds, between the last change and the write.
M.DEBOUNCE_MS = 300

--- The clock in seconds. This is a module field so that a spec can replace it with a fake clock.
M._clock = os.clock

--- Item types whose value is kept in the shell's values table and is saved.
--- Buttons, labels and separators hold no value, and rows and folds only contain other items.
M.VALUE_TYPES = {
    checkbox = true,
    dropdown = true,
    keybind = true,
    number = true,
    radio = true,
    slider = true,
    stepper = true,
    textinput = true,
}

--- The Lua type a saved value must have for each value-bearing item type.
--- A saved value of another type is ignored on load, so a hand-edited or stale file cannot put a
--- string into a checkbox or a boolean into a number.
local VALUE_KIND = {
    checkbox = "boolean",
    dropdown = "string",
    keybind = "string",
    number = "number",
    radio = "string",
    slider = "number",
    stepper = "number",
    textinput = "string",
}

--- Item types for which a nil value is a state of its own, kept as cleared in the snapshot.
--- A number, a slider, a stepper and a keybind treat nil as their default, so they are never saved as cleared.
local CLEARABLE = {
    checkbox = true,
    dropdown = true,
    radio = true,
    textinput = true,
}

local SIDES = { left = true, right = true, top = true, bottom = true }

--- The one pending write. The shell has one store and one snapshot, so a single slot is enough.
local pending = nil

--- True for a value the snapshot keeps: a boolean, a string, or a finite number.
--- Tables are left out, because no value-bearing item stores one and JSON cannot hold every table.
local function IsScalar(value)
    local t = type(value)
    if t == "boolean" or t == "string" then
        return true
    end
    return t == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function HasTab(config, name)
    if type(config) ~= "table" or type(config.tabs) ~= "table" or type(name) ~= "string" then
        return false
    end
    for _, tab in ipairs(config.tabs) do
        if tab == name then
            return true
        end
    end
    return false
end

--- Call visit(item) for every item of a list, and for the children of rows and folds at any depth.
local function EachItem(items, visit)
    if type(items) ~= "table" then
        return
    end
    for _, item in ipairs(items) do
        if type(item) == "table" then
            visit(item)
            if item.type == "row" or item.type == "fold" then
                EachItem(item.items, visit)
            end
        end
    end
end

--- Return a map when value is a table, otherwise an empty table, so a malformed snapshot reads as empty.
local function MapOf(value)
    if type(value) == "table" then
        return value
    end
    return {}
end

--- Return a shallow copy of a table, or an empty table for anything else.
local function Copy(value)
    local copy = {}
    for key, entry in pairs(MapOf(value)) do
        copy[key] = entry
    end
    return copy
end

--- Build the snapshot of a shell state.
--- It starts from a copy of the snapshot read at load, so the saved state of a section that is not
--- registered this session is written back unchanged. The registered sections then overwrite their
--- own part with their current state. Sections are kept in collapsed and folds in folds, because a
--- section id such as "A.more" and the fold "more" in section "A" have the same key.
---@param state table the shell state: config, activeTab, sections, collapsedById, foldCollapsedByKey, values, persistSnapshot
---@return { dock: string|nil, tab: string|nil, collapsed: table<string, boolean>, folds: table<string, boolean>, values: table<string, any>, cleared: table<string, boolean> }
function M.Snapshot(state)
    local config = state.config or {}
    local kept = MapOf(state.persistSnapshot)
    local snapshot = Copy(kept)
    snapshot.dock = config.dock
    snapshot.collapsed = Copy(kept.collapsed)
    snapshot.folds = Copy(kept.folds)
    snapshot.values = Copy(kept.values)
    snapshot.cleared = Copy(kept.cleared)
    if type(state.activeTab) == "string" then
        snapshot.tab = state.activeTab
    end
    local collapsedById = state.collapsedById or {}
    local foldMap = state.foldCollapsedByKey or {}
    local values = state.values or {}
    for _, section in ipairs(state.sections or {}) do
        local sectionId = section.id
        if section.collapsible == true then
            snapshot.collapsed[sectionId] = collapsedById[sectionId] == true
        end
        EachItem(section.items, function(item)
            if item.id == nil then
                return
            end
            local key = Util.ValueKey(sectionId, item.id)
            if item.type == "fold" then
                if type(foldMap[key]) == "boolean" then
                    snapshot.folds[key] = foldMap[key]
                end
            elseif M.VALUE_TYPES[item.type] then
                local value = values[key]
                if IsScalar(value) then
                    snapshot.values[key] = value
                else
                    snapshot.values[key] = nil
                end
                if value == nil and CLEARABLE[item.type] then
                    snapshot.cleared[key] = true
                else
                    snapshot.cleared[key] = nil
                end
            end
        end)
    end
    return snapshot
end

--- Write the kept snapshot's part for one section over its author defaults, once per section.
--- The registry calls this before it seeds a section, so a later Register of the same section
--- keeps what the player changed during the session. A value for an item the section no longer
--- has is ignored, and so is a value whose Lua type does not match its item type.
--- It returns the value keys the snapshot records as cleared, so the registry can clear them again
--- after the seeds have written their defaults.
---@param state table
---@param section table a registered section
---@return string[] cleared the value keys of this section that the snapshot records as cleared
function M.ApplySection(state, section)
    local snapshot = state.persistSnapshot
    if type(snapshot) ~= "table" or type(section) ~= "table" or section.id == nil then
        return {}
    end
    state.persistApplied = state.persistApplied or {}
    if state.persistApplied[section.id] then
        return {}
    end
    state.persistApplied[section.id] = true

    local collapsed = MapOf(snapshot.collapsed)
    local folds = MapOf(snapshot.folds)
    local values = MapOf(snapshot.values)
    local clearedMap = MapOf(snapshot.cleared)
    local cleared = {}
    local sectionId = section.id
    if section.collapsible == true and type(collapsed[sectionId]) == "boolean" then
        state.collapsedById[sectionId] = collapsed[sectionId]
    end
    EachItem(section.items, function(item)
        if item.id == nil then
            return
        end
        local key = Util.ValueKey(sectionId, item.id)
        if item.type == "fold" then
            if type(folds[key]) == "boolean" then
                state.foldCollapsedByKey[key] = folds[key]
            end
        elseif M.VALUE_TYPES[item.type] then
            local value = values[key]
            if IsScalar(value) and type(value) == VALUE_KIND[item.type] then
                state.values[key] = value
            elseif value == nil and clearedMap[key] == true and CLEARABLE[item.type] then
                state.values[key] = nil
                cleared[#cleared + 1] = key
            end
        end
    end)
    return cleared
end

--- Write a snapshot over the author defaults of a state before the first build.
--- The dock and the tab apply now. Each section registered so far gets its part now, and the
--- snapshot is kept on the state so that a section registered later gets its part on Register.
--- A dock that is not an edge, a tab that Init does not list, and a snapshot that is not a table
--- are ignored. It returns the value keys that the snapshot records as cleared in the sections
--- registered so far.
---@param snapshot any the table read from the store, or nil
---@param state table
---@return string[] cleared
function M.Apply(snapshot, state)
    local cleared = {}
    if type(snapshot) ~= "table" then
        return cleared
    end
    state.persistSnapshot = snapshot
    if type(snapshot.dock) == "string" and SIDES[snapshot.dock] and type(state.config) == "table" then
        state.config.dock = snapshot.dock
    end
    if HasTab(state.config, snapshot.tab) then
        state.activeTab = snapshot.tab
    end
    for _, section in ipairs(state.sections or {}) do
        for _, key in ipairs(M.ApplySection(state, section)) do
            cleared[#cleared + 1] = key
        end
    end
    return cleared
end

--- Queue a write of snapshotFn() under the reserved key, ms after this call.
--- A later call moves the write later, so a burst of changes writes once, ms after the last one.
--- The snapshot is taken when the write happens, so it holds the state at that time.
---@param store { Set: fun(key: string, value: any): boolean }
---@param snapshotFn fun(): table
---@param ms number|nil the debounce, DEBOUNCE_MS when nil
function M.Schedule(store, snapshotFn, ms)
    pending = {
        store = store,
        snapshotFn = snapshotFn,
        due = M._clock() + (ms or M.DEBOUNCE_MS) / 1000,
    }
end

---@return boolean
function M.Pending()
    return pending ~= nil
end

--- Drop the pending write without writing it.
--- The shell calls this when autosave is turned off, so a change made just before stays unsaved.
function M.Cancel()
    pending = nil
end

--- Write the pending snapshot when its debounce has ended, or at once when force is true.
--- An error from the store or the snapshot is logged rather than raised, so a broken store
--- cannot stop the shell's tick.
---@param force boolean|nil
---@return boolean wrote true when the store accepted the write
function M.Flush(force)
    if pending == nil then
        return false
    end
    if not force and M._clock() < pending.due then
        return false
    end
    local job = pending
    pending = nil
    local ok, result = pcall(function()
        return job.store.Set(M.KEY, job.snapshotFn())
    end)
    if not ok then
        Util.Log("autosave failed: " .. tostring(result))
        return false
    end
    return result ~= false
end

return M
