--[[
  ModMenu.shell.tabs — optional top-level tab strip.

  Init({ tabs = { "Cheats", "Give" } }) + Register({ tab = "Cheats", ... }).
  Omit tabs = current single-scroll menu.

  Only the active tab's sections are built. Switching queues a rebuild off
  the poll tick (same hitch rule as collapse: never rebuild under a still-down click).
  The last tab survives close and open. It is written to disk only when Init sets autosave = true.

  The strip draws from the resolved tabs style. stock is the original row of filled buttons;
  joined puts the tabs inside one frame, chips gives each tab its own outlined shape, and tabs
  underlines the active one, as StyleLab's MakeChoice draws them. A tab switch rebuilds the
  content, so each tab's look is fixed when it is built and never recoloured.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Theme = require("ModMenu.core.theme")
local Paint = require("ModMenu.core.paint")
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

local H_FILL, H_CENTER = 0, 2
local V_FILL = 0
local VIS_HIDDEN = 2

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local function HasRadius(radius)
    if type(radius) == "table" then
        for i = 1, #radius do
            if (tonumber(radius[i]) or 0) > 0 then
                return true
            end
        end
        return false
    end
    return (tonumber(radius) or 0) > 0
end

--- The joined frame's radius: a few units wider than the tabs inside it, so its curve runs
--- parallel to theirs across the 3 unit padding, as StyleLab draws it.
local function FrameRadius(radius, pill)
    if pill or not HasRadius(radius) then
        return radius
    end
    if type(radius) == "table" then
        local out = {}
        for i = 1, 4 do
            local r = tonumber(radius[i]) or 0
            out[i] = r > 0 and r + 3 or 0
        end
        return out
    end
    return radius + 3
end

--- The resolved tabs style when it draws a themed variant, or nil for the stock strip.
---@param config table
---@return table|nil
local function ThemedTabs(config)
    local resolved = config.resolved
    if type(resolved) ~= "table" or type(resolved.tabs) ~= "table" then
        return nil
    end
    local variant = resolved.tabs.variant
    if variant == "joined" or variant == "chips" or variant == "tabs" then
        return resolved.tabs
    end
    return nil
end

--- The pointer looks of one themed tab. The active joined or chips tab is its mark shape, with
--- hover and pressed derived from it; every other tab is clear and washes in with the text
--- colour. An inactive chip carries the chip outline as its edge. Each look is its own shape,
--- so a rounded tab is never recoloured (field note 30).
local function TabStates(look, palette, active)
    local radius, pill = look.radius or 0, look.pill == true
    if active and look.variant ~= "tabs" then
        return {
            normal = { fill = look.markFill or palette.accent, outline = look.markEdge,
                width = look.markEdge ~= nil and 1 or 0, radius = radius, pill = pill },
        }
    end
    local text = palette.text
    local states = {
        normal = { fill = Alpha(text, 0), radius = radius, pill = pill },
        hover = { fill = Alpha(text, 0.08), radius = radius, pill = pill },
        pressed = { fill = Alpha(text, 0.16), radius = radius, pill = pill },
    }
    if look.variant == "chips" then
        states.edge = { outline = look.edge or palette.line, width = 1 }
    end
    return states
end

--- The content of a tabs-variant tab: its caption over the underline mark. Every tab has the mark,
--- hidden on the inactive ones, so all tabs keep one height.
local function UnderlineContent(outer, name, caption, look, active, textSize, textColor, textSpec)
    local stack = Umg.Construct("/Script/UMG.VerticalBox", outer, name .. "_Stack")
    local text = Umg.Construct("/Script/UMG.TextBlock", stack, name .. "_Text")
    Umg.StyleText(text, textSize, textColor, textSpec)
    Umg.SetLabelText(text, Paint.Caption(caption, textSpec))
    local textSlot = stack:AddChildToVerticalBox(text)
    pcall(function()
        textSlot:SetPadding(Paint.Margin({ 0, 4, 0, 4 }))
        textSlot:SetHorizontalAlignment(H_CENTER)
    end)

    local size = Umg.Construct("/Script/UMG.SizeBox", stack, name .. "_MarkSize")
    local markSpec
    if look.markWidth ~= nil then
        -- A short rounded indicator under the active tab, as in Windows 11.
        markSpec = { fill = look.markFill, radius = 1, pill = true }
    else
        markSpec = { fill = look.markFill }
    end
    local mark = Paint.Box(size, name .. "_Mark", markSpec, 0)
    pcall(function()
        if look.markWidth ~= nil then
            size:SetWidthOverride(look.markWidth)
        end
        size:SetHeightOverride(look.markWidth ~= nil and (look.markHeight or 3) or 2)
        size:SetContent(mark)
    end)
    if not active then
        -- Hidden keeps the mark's space, so the inactive tabs line up with the active one.
        pcall(function()
            mark:SetVisibility(VIS_HIDDEN)
        end)
    end
    local markSlot = stack:AddChildToVerticalBox(size)
    pcall(function()
        markSlot:SetHorizontalAlignment(look.markWidth ~= nil and H_CENTER or H_FILL)
    end)
    return stack, text
end

--- A flat state set drawn as shapes. Paint.StateButton draws flat looks as a recoloured Border
--- around a Button with the engine's padding, and shape looks inside a Button with none, so one
--- strip mixing both would give tabs of different heights and caption padding. Each look gets a
--- 1 unit outline in its own fill colour, which draws the same rectangle and makes it a shape.
--- Hover and pressed are derived first, so each keeps an outline of its own colour.
local function AsShapes(states)
    local normal = states.normal
    local derivedHover, derivedPressed = Theme.FillStates(normal.fill)
    local function Outlined(spec, fill)
        local out = {}
        for k, v in pairs(spec or normal) do
            out[k] = v
        end
        out.fill = fill
        out.outline = fill
        out.width = 1
        return out
    end
    return {
        normal = Outlined(normal, normal.fill),
        hover = Outlined(states.hover, states.hover and states.hover.fill or derivedHover),
        pressed = Outlined(states.pressed, states.pressed and states.pressed.fill or derivedPressed),
        edge = states.edge,
    }
end

local function BuildThemedStrip(S, contentBox, suffix, look)
    local config = S.config
    local resolved = config.resolved
    local palette = resolved.palette or {}
    local body = resolved.body or {}
    local touch = config.pointerMode == "touch"
    local spacing = config.spacing
    local tabHeight = spacing.tabHeight
    local tabGap = touch and spacing.tabGapTouch or spacing.tabGap
    local tabPad = touch and spacing.tabPadTouch or spacing.tabPad
    local variant = look.variant

    local row = Umg.Construct("/Script/UMG.HorizontalBox", contentBox, "ModMenu_Tabs_" .. suffix)
    local host = row
    if variant == "joined" then
        local ghost = resolved.button ~= nil and resolved.button.variant == "ghost"
        local edge = look.edge or (ghost and Alpha(palette.accent, 0.6) or nil)
        local frame = Paint.Box(contentBox, "ModMenu_TabsFrame_" .. suffix, {
            fill = look.trackFill or (ghost and Alpha(palette.accent, 0) or palette.surface),
            outline = edge,
            width = edge ~= nil and 1 or 0,
            radius = FrameRadius(look.radius or 0, look.pill == true),
            pill = look.pill == true,
        }, 3)
        pcall(function()
            local slot = frame:SetContent(row)
            slot:SetHorizontalAlignment(H_FILL)
            slot:SetVerticalAlignment(V_FILL)
        end)
        host = frame
    end
    contentBox:AddChildToVerticalBox(host)

    -- The tab caption is the body text a size smaller, as in StyleLab; with no theme size it is fontItem.
    local textSize = Paint.TextSize(config, body.size ~= nil and body.size - 1 or nil, "fontItem")

    -- Flat or shape is decided once for the strip, so every tab is built the same way.
    local tabStates = {}
    local anyShapes = false
    for i, name in ipairs(config.tabs) do
        tabStates[i] = TabStates(look, palette, name == S.activeTab)
        if Paint.NeedsShapes(tabStates[i]) then
            anyShapes = true
        end
    end
    if anyShapes then
        for i, states in ipairs(tabStates) do
            if not Paint.NeedsShapes(states) then
                tabStates[i] = AsShapes(states)
            end
        end
    end

    for i, name in ipairs(config.tabs) do
        local active = name == S.activeTab
        local textColor
        if variant == "tabs" then
            textColor = active and (look.tabText or look.markFill) or palette.muted
        else
            textColor = active and (look.markText or palette.accentText) or palette.text
        end
        local ctrlName = "ModMenu_Tab" .. tostring(i) .. "_" .. suffix
        local tabHost = row
        local size = nil
        if touch then
            size = Umg.Construct("/Script/UMG.SizeBox", row, "ModMenu_TabSize" .. tostring(i) .. "_" .. suffix)
            pcall(function()
                size:SetMinDesiredHeight(tabHeight)
            end)
            tabHost = size
        end

        local states = tabStates[i]
        local button, text
        if variant == "tabs" then
            local content
            content, text = UnderlineContent(tabHost, ctrlName, name, look, active, textSize, textColor, body)
            button = Paint.StateButton(tabHost, ctrlName, states, content)
        else
            button = Paint.StateButton(tabHost, ctrlName, states, name,
                { color = textColor, size = textSize, textSpec = body, pad = { 8, 5, 8, 5 } })
            text = button.label
        end

        if size ~= nil then
            -- Button must fill the SizeBox or the extra height is not hittable.
            pcall(function()
                local contentSlot = size:SetContent(button.root)
                contentSlot:SetHorizontalAlignment(H_FILL)
                contentSlot:SetVerticalAlignment(V_FILL)
            end)
            if button.flat then
                -- A flat tab's fill is the Border outside the Button, so padding the Button grows the
                -- hit area inside the fill. A shape tab draws inside the Button, where padding would
                -- shrink the shape, so it keeps the SizeBox height alone.
                pcall(function()
                    button.widget:SetPadding({ Left = tabGap, Top = tabPad, Right = tabGap, Bottom = tabPad })
                end)
            end
        end

        -- Joined tabs sit close inside their frame; chips and underlined tabs keep the spacing gap.
        local gap = variant == "joined" and 2 or tabGap
        local slot = row:AddChildToHorizontalBox(size or button.root)
        pcall(function()
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetPadding({ Left = (i == 1) and 0 or gap, Top = 0, Right = 0, Bottom = 0 })
            slot:SetVerticalAlignment(V_FILL)
        end)

        button.kind = "tab"
        button.tabId = name
        button.label = text
        table.insert(S.liveControls, button)
    end

    Umg.AddSpacer(contentBox, "ModMenu_TabPad_" .. suffix, tabPad)
end

--- Horizontal tab buttons under title / dock. Fill-width so three names share the row.
function M.BuildStrip(S, contentBox, suffix)
    M.Ensure(S)
    if not M.Enabled(S) then
        return
    end
    local look = ThemedTabs(S.config)
    if look ~= nil then
        BuildThemedStrip(S, contentBox, suffix, look)
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
            -- The stock tab is a recoloured Border, so Paint.TrackPointer repaints it as Umg.TrackPointer did.
            flat = true,
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
    Paint.TrackPointer(ctrl)
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
