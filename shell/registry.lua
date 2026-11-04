--[[
  ModMenu.shell.registry — sections, values, Register, Get/Set, live widget apply.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local Options = require("ModMenu.core.options")
local Tooltip = require("ModMenu.core.tooltip")
local Persist = require("ModMenu.core.persist")
local ItemState = require("ModMenu.core.itemstate")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Build = require("ModMenu.shell.build")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local ToPlainString = Util.ToPlainString
local ValueKey = Util.ValueKey
local SetLabelText = Umg.SetLabelText
local NormalizeOptions = Options.NormalizeOptions
local Dropdown = Widgets.get("dropdown")
local Button = Widgets.get("button")

local M = {}

--- Check the tooltip, enabled and visible fields of an item and of the children of a row or fold, at any depth.
--- The registry does this for every type, because those fields are common to all of them.
--- A child that is not a table is skipped here, so the row or fold validate reports it in its own words.
local function ValidateTooltips(item, prefix)
    Tooltip.Validate(item, prefix)
    ItemState.Validate(item, prefix)
    if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
        for i, child in ipairs(item.items) do
            if type(child) == "table" then
                ValidateTooltips(child, string.format("%s.items[%d]", prefix, i))
            end
        end
    end
end

local function ValidateItem(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if type(item) ~= "table" then
        error(prefix .. " must be a table")
    end
    ValidateTooltips(item, prefix)
    local t = item.type
    local widget = Widgets.get(t)
    if not widget then
        error(prefix .. " unsupported type '" .. tostring(t) .. "' (" .. Widgets.typeList() .. ")")
    end
    if widget.validate then
        widget.validate(item, sectionId, index)
    end
end

--- Walk top-level, fold, and row children (fold may contain a row).
local function FindItemById(items, itemId, typeName)
    for _, item in ipairs(items or {}) do
        if item.id == itemId and (typeName == nil or item.type == typeName) then
            return item
        end
        if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
            local found = FindItemById(item.items, itemId, typeName)
            if found then
                return found
            end
        end
    end
    return nil
end

local function ValidateSection(section)
    if type(section) ~= "table" then
        error("Register() expects a section table")
    end
    if section.id == nil or section.id == "" then
        error("Register() section requires .id")
    end
    if type(section.items) ~= "table" then
        error("Register(" .. tostring(section.id) .. ") requires .items array")
    end
    Collapse.Validate(section)
    for i, item in ipairs(section.items) do
        ValidateItem(item, section.id, i)
    end
end

--- Rebuild now if open; otherwise mark dirty so the next Open rebuilds
--- (close/open keeps the UMG tree).
local function EnsureRebuildFn(S)
    if S.rebuildFn ~= nil then
        return S.rebuildFn
    end
    S.rebuildFn = Util.PinFn(function()
        local ok, err = pcall(function()
            if Build.Ensure(S) then
                Build.BuildContent(S)
                Session.EnsureVisible(S)
                Input.ClearClickState()
            end
        end)
        if not ok then
            Log("rebuild failed: " .. tostring(err))
            Session.EnsureVisible(S)
        end
    end)
    return S.rebuildFn
end

local function RebuildIfOpen(S)
    if not S.menuOpen then
        if IsValid(S.menuRoot) then
            S.contentDirty = true
        end
        return
    end
    ExecuteInGameThread(EnsureRebuildFn(S))
end

--- Apply a stored value to any live control with that valueKey.
local function ApplyLive(S, vkey, value)
    local ctx = S.makeWidgetCtx()
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.valueKey == vkey then
            local widget = Widgets.get(ctrl.kind)
            if widget and widget.apply then
                widget.apply(ctrl, value, ctx)
            end
        end
    end
end

--- Set each listed value key to nil, for the values a saved snapshot records as cleared.
local function ClearKeys(S, keys)
    for _, key in ipairs(keys or {}) do
        S.values[key] = nil
    end
end

function M.Register(S, section)
    ValidateSection(section)

    local copy = {
        id = section.id,
        title = section.title or section.id,
        items = section.items,
        collapsible = section.collapsible == true,
        collapsed = section.collapsed == true,
        description = section.description,
        prefix = section.prefix,
        onToggle = section.onToggle,
        tab = Tabs.ResolveSectionTab(S, section),
    }

    -- The saved snapshot goes in before the seeds, which keep a value already present, so it
    -- overrides the author defaults. A section gets its part only on its first Register.
    local cleared = Persist.ApplySection(S, copy)

    Collapse.Seed(S, copy)

    -- Seed defaults into values store.
    for _, item in ipairs(copy.items) do
        local widget = Widgets.get(item.type)
        if widget and widget.seed then
            widget.seed(copy.id, item, S.values)
        end
    end
    -- A seed writes the default over a nil value, so a value the player cleared is cleared again here.
    ClearKeys(S, cleared)

    local existing = S.sectionIndexById[copy.id]
    local oldTab = existing and S.sections[existing].tab
    if existing then
        S.sections[existing] = copy
        Debug("Updated section: " .. copy.id)
    else
        table.insert(S.sections, copy)
        S.sectionIndexById[copy.id] = #S.sections
        Debug("Registered section: " .. copy.id .. " (" .. tostring(#copy.items) .. " items)")
    end

    -- Hidden-tab Register must not rebuild the active tab's tree.
    local needsUi = (not Tabs.Enabled(S))
        or Tabs.SectionVisible(S, copy)
        or (oldTab ~= nil and oldTab == S.activeTab)
    if needsUi then
        RebuildIfOpen(S)
    end
end

function M.Get(S, sectionId, itemId)
    return S.values[ValueKey(sectionId, itemId)]
end

--- Find the registered number item for a value key, or nil when the id is not a number item.
local function FindNumberItem(S, sectionId, itemId)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return nil
    end
    return FindItemById(S.sections[idx].items, itemId, "number")
end

--- Find the registered item of one type for a value key, or nil when the id is not an item of that type.
local function FindTypedItem(S, sectionId, itemId, typeName)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return nil
    end
    return FindItemById(S.sections[idx].items, itemId, typeName)
end

function M.Set(S, sectionId, itemId, value)
    local vkey = ValueKey(sectionId, itemId)
    -- The store keeps the value before the widget sees it, so a number item gets a rounded number
    -- inside its range here, whether the caller passed a number or text.
    -- A value that is not numeric is ignored, leaving the stored value and the live control unchanged.
    -- A nil value resets the item to its default, which the number widget's coerce returns for nil.
    -- Before Register no item is known, so the value is stored as given and the widget's seed coerces it in Register.
    local numberItem = FindNumberItem(S, sectionId, itemId)
    if numberItem then
        value = Widgets.get("number")._coerce(value, numberItem)
        if value == nil then
            return
        end
    end
    -- A radio value that no option holds raises here, before the write, so Get keeps the previous value.
    local radioItem = FindTypedItem(S, sectionId, itemId, "radio")
    if radioItem then
        value = Widgets.get("radio")._check(value, radioItem)
    end
    -- A slider value is snapped and clamped here, as a number is, so the stored value does not depend on a built control.
    local sliderItem = FindTypedItem(S, sectionId, itemId, "slider")
    if sliderItem then
        value = Widgets.get("slider")._coerce(value, sliderItem)
        if value == nil then
            return
        end
    end
    S.values[vkey] = value
    ApplyLive(S, vkey, value)
    Session.NoteChange(S)
end

--- Write a saved snapshot over the sections registered so far, then seed them again.
--- The seeds keep the snapshot's values and coerce them as they coerce a value set before
--- Register, so a saved number outside its range comes back inside it.
---@param snapshot any
function M.ApplySnapshot(S, snapshot)
    local cleared = Persist.Apply(snapshot, S)
    for _, section in ipairs(S.sections) do
        for _, item in ipairs(section.items) do
            local widget = Widgets.get(item.type)
            if widget and widget.seed then
                widget.seed(section.id, item, S.values)
            end
        end
    end
    -- A seed writes the default over a nil value, so a value the snapshot records as cleared is cleared again here.
    ClearKeys(S, cleared)
end

function M.SetLabel(S, sectionId, itemId, text)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "label")
    if not item then
        return false
    end
    item.label = tostring(text)
    local vkey = ValueKey(sectionId, itemId)
    local ctx = S.makeWidgetCtx()
    local labelWidget = Widgets.get("label")
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "label" and ctrl.valueKey == vkey and IsValid(ctrl.widget) then
            if labelWidget and labelWidget.apply then
                labelWidget.apply(ctrl, item.label, ctx)
            end
        end
    end
    return true
end

function M.SetButtonLabel(S, sectionId, itemId, text)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    item.label = tostring(text)
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "button"
            and ctrl.sectionId == sectionId
            and ctrl.item
            and ctrl.item.id == itemId
        then
            -- Do not gate on IsValid(labelWidget) — Button child TextBlocks often report invalid.
            SetLabelText(ctrl.labelWidget, item.label)
            return true
        end
    end
    return true
end

local function SyncLiveButton(S, sectionId, itemId)
    local ctx = S.makeWidgetCtx()
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "button"
            and ctrl.sectionId == sectionId
            and ctrl.item
            and ctrl.item.id == itemId
        then
            if Button and Button.applyChrome then
                Button.applyChrome(ctrl, ctx)
            end
            return
        end
    end
end

--- Set one common flag of an item and apply the section's effective states in place, with no rebuild.
--- A parent's state reaches its children, so the whole section tree is applied.
---@param field string "enabled" or "visible"
---@return boolean found false when the section or the item is not registered
local function SetItemFlag(S, sectionId, itemId, field, value)
    -- A nil id would match the first item that has no id, such as a separator.
    if itemId == nil then
        return false
    end
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, nil)
    if not item then
        return false
    end
    item[field] = value and true or false
    ItemState.ApplyItems(S, section.items, false)
    return true
end

--- Enable or disable any item. A disabled item draws dim and ignores input; a row or fold passes the flag to its children.
function M.SetEnabled(S, sectionId, itemId, enabled)
    return SetItemFlag(S, sectionId, itemId, "enabled", enabled)
end

--- Show or hide any item. A hidden item takes no space and keeps its value.
function M.SetVisible(S, sectionId, itemId, visible)
    return SetItemFlag(S, sectionId, itemId, "visible", visible)
end

--- Kept so a host that calls it still works; it is SetEnabled for a button.
function M.SetButtonEnabled(S, sectionId, itemId, enabled)
    return M.SetEnabled(S, sectionId, itemId, enabled)
end

function M.SetButtonVariant(S, sectionId, itemId, variant)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    local normalized = Button.NormalizeVariant(variant)
    if normalized == nil then
        error("SetButtonVariant: variant must be default|primary|secondary|success|danger|warning|info")
    end
    item.variant = normalized
    SyncLiveButton(S, sectionId, itemId)
    return true
end

function M.SetButtonActive(S, sectionId, itemId, active)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "button")
    if not item then
        return false
    end
    item.active = active and true or false
    SyncLiveButton(S, sectionId, itemId)
    return true
end

--- Replace dropdown options.
--- Searchable dropdowns refresh rows in place when live; others rebuild the panel.
function M.SetOptions(S, sectionId, itemId, options, selectedValue)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        return false
    end
    local section = S.sections[idx]
    local item = FindItemById(section.items, itemId, "dropdown")
    if not item then
        return false
    end
    if type(options) ~= "table" then
        error("SetOptions requires an options array")
    end
    local list = NormalizeOptions(options)
    item.options = list
    local vkey = ValueKey(sectionId, itemId)
    -- An empty list has nothing to select, so the value is cleared and the dropdown shows its placeholder.
    if #list == 0 or selectedValue == false then
        S.values[vkey] = nil
        item.default = nil
    elseif selectedValue ~= nil then
        local plain = ToPlainString(selectedValue) or selectedValue
        S.values[vkey] = plain
        item.default = plain
    end

    -- Prefer in-place refresh for searchable lists (category filter, etc.).
    -- Live pickers still exist while the menu is closed (tree is kept).
    local live = nil
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "dropdown" and ctrl.valueKey == vkey then
            live = ctrl
            break
        end
    end

    if live and live.searchable and live.listBox ~= nil then
        -- False tells the live picker to show its placeholder, matching the cleared store value.
        local liveSelected = selectedValue
        if #list == 0 then
            liveSelected = false
        end
        Dropdown.refreshLive(live, list, liveSelected, S.values, vkey)
        Debug(string.format(
            "SetOptions(%s.%s) refreshed searchable list (%d options)",
            tostring(sectionId),
            tostring(itemId),
            #list
        ))
        return true
    end

    if S.menuOpen and Tabs.Enabled(S) and not Tabs.SectionVisible(S, section) then
        return true
    end

    if S.menuOpen then
        ExecuteInGameThread(EnsureRebuildFn(S))
        Debug(string.format(
            "SetOptions(%s.%s) scheduled rebuild with %d options",
            tostring(sectionId),
            tostring(itemId),
            #list
        ))
    elseif IsValid(S.menuRoot) then
        S.contentDirty = true
    end
    return true
end

function M.ListSections(S)
    local ids = {}
    for _, section in ipairs(S.sections) do
        table.insert(ids, section.id)
    end
    return ids
end

return M
