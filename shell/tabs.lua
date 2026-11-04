--[[
  ModMenu.shell.tabs — optional top-level tab strip.

  Init({ tabs = { "Cheats", "Give" } }) + Register({ tab = "Cheats", ... }).
  Omit tabs = current single-scroll menu.

  Only the active tab's sections are built. Switching queues a rebuild off
  the poll tick (same hitch rule as collapse: never rebuild under a still-down click).
  The last tab survives close and open. It is written to disk only when Init sets autosave = true.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Theme = require("ModMenu.core.theme")
local Session = require("ModMenu.shell.session")

local Debug = Util.Debug
local Construct = Umg.Construct
local AddSpacer = Umg.AddSpacer

local M = {}

---@return boolean
function M.Enabled(S)
    return type(S.config.tabs) == "table" and #S.config.tabs > 0
end

---@return boolean
function M.Has(S, name)
    if not M.Enabled(S) or type(name) ~= "string" then
        return false
    end
    for _, tab in ipairs(S.config.tabs) do
        if tab == name then
            return true
        end
    end
    return false
end

--- Seed / repair S.activeTab against the current Init list.
function M.Ensure(S)
    if not M.Enabled(S) then
        S.activeTab = nil
        return
    end
    if M.Has(S, S.activeTab) then
        return
    end
    S.activeTab = S.config.tabs[1]
end

--- Map Register({ tab }) onto an Init tab. Omit tab = first tab.
---@return string|nil
function M.ResolveSectionTab(S, section)
    if not M.Enabled(S) then
        return nil
    end
    local tab = section.tab
    if tab == nil or tab == "" then
        return S.config.tabs[1]
    end
    if type(tab) ~= "string" then
        error("Register(" .. tostring(section.id) .. ") tab must be a string")
    end
    if not M.Has(S, tab) then
        error("Register(" .. tostring(section.id) .. ") tab " .. tab
            .. " is not in Init({ tabs = ... })")
    end
    return tab
end

---@return boolean
function M.SectionVisible(S, section)
    if not M.Enabled(S) then
        return true
    end
    M.Ensure(S)
    return section ~= nil and section.tab == S.activeTab
end

--- Horizontal tab buttons under title / dock. Fill-width so three names share the row.
function M.BuildStrip(S, contentBox, suffix)
    M.Ensure(S)
    if not M.Enabled(S) then
        return
    end
    local colors = Theme.Of(S.config)
    local touch = S.config.pointerMode == "touch"
    -- Tab gaps and paddings come from this instance's spacing, with a touch variant for finger-sized targets.
    -- Desktop buttons keep their text height, so tabHeight applies in touch mode only.
    local spacing = S.config.spacing
    local tabHeight = spacing.tabHeight
    local tabGap = touch and spacing.tabGapTouch or spacing.tabGap
    local tabPad = touch and spacing.tabPadTouch or spacing.tabPad
    local row = Construct("/Script/UMG.HorizontalBox", contentBox, "ModMenu_Tabs_" .. suffix)
    contentBox:AddChildToVerticalBox(row)

    for i, name in ipairs(S.config.tabs) do
        local active = name == S.activeTab
        local bg = active and colors.buttonBgActive or colors.buttonBg
        local fg = active and colors.buttonTextActive or colors.buttonText
        local host = row
        local size = nil
        if touch then
            size = Construct("/Script/UMG.SizeBox", row, "ModMenu_TabSize" .. tostring(i) .. "_" .. suffix)
            pcall(function()
                size:SetMinDesiredHeight(tabHeight)
            end)
            host = size
        end
        local fill, btn, lbl = Umg.CreateFilledButton(
            host,
            "ModMenu_Tab" .. tostring(i) .. "_" .. suffix,
            name,
            fg,
            S.config.fontItem
        )
        if size ~= nil then
            -- Button must fill the SizeBox or the extra height is not hittable.
            local contentSlot
            pcall(function()
                contentSlot = size:SetContent(fill)
            end)
            pcall(function()
                if contentSlot ~= nil then
                    contentSlot:SetHorizontalAlignment(0) -- Fill
                    contentSlot:SetVerticalAlignment(0)
                end
            end)
            pcall(function()
                btn:SetPadding({ Left = tabGap, Top = tabPad, Right = tabGap, Bottom = tabPad })
            end)
        end
        local slot = row:AddChildToHorizontalBox(size or fill)
        pcall(function()
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetPadding({
                Left = (i == 1) and 0 or tabGap,
                Top = 0,
                Right = 0,
                Bottom = 0,
            })
            slot:SetVerticalAlignment(2)
        end)
        local tabCtrl = {
            kind = "tab",
            widget = btn,
            fill = fill,
            label = lbl,
            tabId = name,
        }
        Umg.SetFill(tabCtrl, bg)
        table.insert(S.liveControls, tabCtrl)
    end

    AddSpacer(contentBox, "ModMenu_TabPad_" .. suffix, tabPad)
end

function M.QueueSelect(S, tabId)
    if not M.Enabled(S) or tabId == nil then
        return
    end
    if tabId == S.activeTab then
        return
    end
    if S.pendingTabId ~= nil then
        return
    end
    S.pendingTabId = tabId
end

--- Apply a tab change. Lazy-requires build so this module can be loaded from build.lua.
function M.Apply(S, tabId)
    if not M.Enabled(S) or tabId == nil then
        return
    end
    M.Ensure(S)
    if not M.Has(S, tabId) then
        return
    end
    if tabId == S.activeTab then
        return
    end
    S.activeTab = tabId
    Debug("Tab -> " .. tabId)
    Session.NoteChange(S)
    if not S.menuOpen then
        if Util.IsValid(S.menuRoot) then
            S.contentDirty = true
        end
        return
    end
    local Build = require("ModMenu.shell.build")
    Build.BuildContent(S)
    Input.ClearClickState()
    InputMode.Reclaim()
end

--- Drain a queued tab click off the poll tick (collapse-style delay).
function M.Flush(S)
    local tabId = S.pendingTabId
    if tabId == nil then
        return
    end
    S.pendingTabId = nil
    table.insert(S.tabApplyQueue, tabId)
    if S.tabApplyFn == nil then
        S.tabApplyFn = Util.PinFn(function()
            S.tabApplyScheduled = false
            local queue = S.tabApplyQueue
            S.tabApplyQueue = {}
            local last = queue[#queue]
            if last ~= nil then
                M.Apply(S, last)
            end
        end)
    end
    if S.tabApplyScheduled then
        return
    end
    S.tabApplyScheduled = true
    ExecuteInGameThreadWithDelay(1, S.tabApplyFn)
end

--- Host SetTab: apply now so GetTab matches. Click path still queues (Flush).
---@return boolean
function M.Select(S, tabId)
    if not M.Enabled(S) then
        error("ModMenu.SetTab: Init({ tabs = ... }) was not set")
    end
    if type(tabId) ~= "string" or tabId == "" then
        error("ModMenu.SetTab: tab must be a non-empty string")
    end
    if not M.Has(S, tabId) then
        error("ModMenu.SetTab: " .. tabId .. " is not in Init({ tabs = ... })")
    end
    M.Ensure(S)
    if tabId == S.activeTab then
        return true
    end
    M.Apply(S, tabId)
    return true
end

function M.Poll(S, ctrl)
    Umg.TrackPointer(ctrl)
    if Input.ReleaseClick(ctrl, ctrl.widget) then
        Input.DebugClick("release", ctrl, ctrl.widget)
        M.QueueSelect(S, ctrl.tabId)
        InputMode.Reclaim()
        Input.IgnoreClicks(2)
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    local consumed, fireNow = Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        Input.DebugClick("latch-hover", ctrl, ctrl.widget)
        Input.SuppressPressEdge(ctrl)
        M.QueueSelect(S, ctrl.tabId)
        InputMode.Reclaim()
        Input.IgnoreClicks(2)
    end
    return consumed
end

return M
