--[[
  ModMenu.shell.collapse — collapsible section headers.

  Opt-in via Register({ collapsible = true, collapsed = true? }).
  The session remembers open or closed per section id. It is saved to disk only when Init sets
  autosave = true.

  Same pattern as dropdowns: keep the header widget, show/hide a body box.
  Do not rebuild the tree on toggle — that destroyed the header under a
  still-down click and caused an open/close flicker.

  Section headers draw from the resolved section style. The stock variant is the library's
  original header, and label, rule and bar are the themed variants. widgets/fold.lua draws its
  fold headers through the same helpers, so a fold matches its section.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Theme = require("ModMenu.core.theme")
local Input = require("ModMenu.core.input")
local Paint = require("ModMenu.core.paint")
local Session = require("ModMenu.shell.session")

local Debug = Util.Debug
local SafeCall = Util.SafeCall

-- Isolated on the right like a shadcn chevron. ASCII so game fonts stay valid.
local MARK_COLLAPSED = "+"
local MARK_EXPANDED = "-"

local M = {}

function M.IsCollapsible(section)
    return section ~= nil and section.collapsible == true
end

function M.IsCollapsed(S, section)
    if not M.IsCollapsible(section) then
        return false
    end
    return S.collapsedById[section.id] == true
end

--- Seed session state once. Re-Register keeps the player's current open/closed.
function M.Seed(S, section)
    if not M.IsCollapsible(section) then
        return
    end
    if S.collapsedById[section.id] == nil then
        S.collapsedById[section.id] = section.collapsed == true
    end
end

function M.Mark(collapsed)
    if collapsed then
        return MARK_COLLAPSED
    end
    return MARK_EXPANDED
end

--- The title a section shows: its title or id, with the prefix before it when the section has one.
---@param section table
---@return string
function M.TitleText(section)
    local title = tostring(section.title or section.id)
    if type(section.prefix) == "string" and section.prefix ~= "" then
        return section.prefix .. " " .. title
    end
    return title
end

function M.Validate(section)
    local id = tostring(section.id)
    if section.collapsible ~= nil and type(section.collapsible) ~= "boolean" then
        error("Register(" .. id .. ") collapsible must be a boolean")
    end
    if section.collapsed ~= nil and type(section.collapsed) ~= "boolean" then
        error("Register(" .. id .. ") collapsed must be a boolean")
    end
    if section.onToggle ~= nil and type(section.onToggle) ~= "function" then
        error("Register(" .. id .. ") onToggle must be a function")
    end
    if section.collapsed == true and section.collapsible ~= true then
        error("Register(" .. id .. ") collapsed=true requires collapsible=true")
    end
    if section.description ~= nil and type(section.description) ~= "string" then
        error("Register(" .. id .. ") description must be a string")
    end
    if section.prefix ~= nil and type(section.prefix) ~= "string" then
        error("Register(" .. id .. ") prefix must be a string")
    end
end

local function FindHeader(S, sectionId)
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.kind == "collapse" and ctrl.sectionId == sectionId then
            return ctrl
        end
    end
    return nil
end

local function SetBodyVisible(ctrl, collapsed)
    if ctrl == nil or ctrl.body == nil then
        return
    end
    pcall(function()
        ctrl.body:SetVisibility(collapsed and Session.VIS_COLLAPSED or Session.VIS_VISIBLE)
    end)
    if ctrl.mark ~= nil then
        Umg.SetLabelText(ctrl.mark, M.Mark(collapsed))
    end
end

--- Queue a toggle. Apply in Flush after the poll loop (dropdown-style: one
--- click must not both press-edge and latch).
function M.QueueToggle(S, sectionId, source)
    if S.pendingCollapseId ~= nil then
        Debug(string.format(
            "collapse queue skip id=%s via=%s (already pending id=%s via=%s)",
            tostring(sectionId),
            tostring(source),
            tostring(S.pendingCollapseId),
            tostring(S.pendingCollapseSource)
        ))
        return
    end
    S.pendingCollapseId = sectionId
    S.pendingCollapseSource = source
    Debug(string.format("collapse queue id=%s via=%s", tostring(sectionId), tostring(source)))
end

function M.Poll(S, ctrl)
    Paint.TrackPointer(ctrl)
    if Input.ReleaseClick(ctrl, ctrl.widget) then
        Input.DebugClick("release", ctrl, ctrl.widget)
        Input.SuppressPressEdge(ctrl)
        Input.IgnoreClicks(2)
        M.QueueToggle(S, ctrl.sectionId, "press")
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    local consumed, fireNow = Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        Input.DebugClick("latch-hover", ctrl, ctrl.widget)
        Input.SuppressPressEdge(ctrl)
        Input.IgnoreClicks(2)
        M.QueueToggle(S, ctrl.sectionId, "latch")
    end
    return consumed
end

function M.Apply(S, sectionId, source)
    local idx = S.sectionIndexById[sectionId]
    if not idx then
        Debug(string.format("collapse apply miss id=%s via=%s (no section)", tostring(sectionId), tostring(source)))
        return
    end
    local section = S.sections[idx]
    if not M.IsCollapsible(section) then
        return
    end

    local collapsed = not M.IsCollapsed(S, section)
    S.collapsedById[sectionId] = collapsed
    section.collapsed = collapsed
    Session.NoteChange(S)

    local ctrl = FindHeader(S, sectionId)
    SetBodyVisible(ctrl, collapsed)
    if ctrl then
        Input.SuppressPressEdge(ctrl)
    end
    Input.IgnoreClicks(2)

    Debug(string.format(
        "collapse apply id=%s via=%s %s gen=%d header=%s",
        tostring(sectionId),
        tostring(source),
        collapsed and "close" or "open",
        S.contentGen or 0,
        ctrl ~= nil and "live" or "missing"
    ))
    SafeCall(section.onToggle, collapsed)
end

function M.Flush(S)
    local sectionId = S.pendingCollapseId
    if sectionId == nil then
        return
    end
    local source = S.pendingCollapseSource
    S.pendingCollapseId = nil
    S.pendingCollapseSource = nil
    -- Do not SetVisibility inside LoopInGameThreadWithDelay. Opening a large
    -- always-built body (Add, Give, …) hitches UMG on this EngineTick; UE4SS
    -- then fails get_function_ref on a delayed callback and removes the hook.
    table.insert(S.collapseApplyQueue, { id = sectionId, source = source })
    if S.collapseApplyFn == nil then
        S.collapseApplyFn = Util.PinFn(function()
            S.collapseApplyScheduled = false
            local queue = S.collapseApplyQueue
            S.collapseApplyQueue = {}
            for _, job in ipairs(queue) do
                M.Apply(S, job.id, job.source)
            end
        end)
    end
    if S.collapseApplyScheduled then
        return
    end
    S.collapseApplyScheduled = true
    ExecuteInGameThreadWithDelay(1, S.collapseApplyFn)
end

local function AddHeaderText(row, name, text, fontSize, color, fill, spacing)
    local block = Umg.Construct("/Script/UMG.TextBlock", row, name)
    Umg.StyleText(block, fontSize, color)
    Umg.SetLabelText(block, text)
    pcall(function()
        -- ETextJustify::Left / Right
        block:SetJustification(fill and 0 or 2)
    end)

    local host = block
    if not fill then
        local size = Umg.Construct("/Script/UMG.SizeBox", row, name .. "_Size")
        pcall(function()
            size:SetWidthOverride(18)
            size:SetContent(block)
        end)
        host = size
    end

    local slot = row:AddChildToHorizontalBox(host)
    pcall(function()
        if fill then
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetHorizontalAlignment(0) -- Left
        else
            slot:SetSize({ SizeRule = 0, Value = 0.0 })
            slot:SetHorizontalAlignment(2) -- Right
        end
        slot:SetVerticalAlignment(2) -- Center
        -- The title carries the whole gap to the mark as its right padding, so the mark's left padding is 0.
        local padX = spacing.sectionHeaderPadX
        local padY = spacing.sectionHeaderPadY
        slot:SetPadding({
            Left = fill and padX or 0,
            Top = padY,
            Right = fill and spacing.sectionHeaderGap or padX,
            Bottom = padY,
        })
    end)
    return block
end

------------------------------------------------------------------------------------------
-- Themed section headers
------------------------------------------------------------------------------------------

local H_LEFT, H_RIGHT = 1, 3
local V_CENTER = 2

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

--- The resolved section style when it draws a themed variant, or nil for the stock header. A
--- config without a resolved style, as some specs build, draws the stock header too.
---@param config table
---@return table|nil section, table|nil palette
function M.ThemedSection(config)
    local resolved = config ~= nil and config.resolved or nil
    if type(resolved) ~= "table" or type(resolved.section) ~= "table" then
        return nil, nil
    end
    local variant = resolved.section.variant
    if variant == nil or variant == "stock" then
        return nil, nil
    end
    return resolved.section, resolved.palette or {}
end

--- The pointer looks of a themed header button. A bar keeps its band and derives hover and
--- pressed from it, as the stock header does. Label and rule headers are clear and wash in with
--- the text colour, as StyleLab's buttons do. Every look is flat, so the header stays one
--- recoloured Border.
---@param sec table resolved section style
---@param palette table resolved palette
---@return table states for Paint.StateButton
function M.HeaderStates(sec, palette)
    if sec.variant == "bar" then
        return { normal = { fill = sec.fill } }
    end
    local wash = palette.text or sec.color
    return {
        normal = { fill = Alpha(wash, 0) },
        hover = { fill = Alpha(wash, 0.08) },
        pressed = { fill = Alpha(wash, 0.16) },
    }
end

-- Header parts whose failure was already logged, so a part that fails on every build is named once.
local loggedParts = {}

--- Build one part of a themed header guarded, so a failed part logs once per session and the rest
--- of the header still builds. Returns what fn returned, or nil when it failed.
local function TryPart(part, fn)
    local ok, result = pcall(fn)
    if ok then
        return result
    end
    if not loggedParts[part] then
        loggedParts[part] = true
        Util.Log("section header " .. part .. " failed: " .. tostring(result))
    end
    return nil
end

local function AddRowText(row, name, text, size, color, textSpec, pad, fill, halign)
    local block = Umg.Construct("/Script/UMG.TextBlock", row, name)
    Umg.StyleText(block, size, color, textSpec)
    Umg.SetLabelText(block, text)
    local slot = row:AddChildToHorizontalBox(block)
    pcall(function()
        slot:SetSize({ SizeRule = fill and 1 or 0, Value = fill and 1.0 or 0.0 })
        slot:SetHorizontalAlignment(halign or H_LEFT)
        slot:SetVerticalAlignment(V_CENTER)
        slot:SetPadding(Paint.Margin(pad))
    end)
    return block
end

--- The row inside a themed section or fold header: the title, a rule line for the rule variant,
--- and the + or - mark when the header folds. opts: config, sec, title, mark (string or nil),
--- themeSize (the theme's text size or nil), fontKey ("fontSection" or "fontHint"), titlePad and
--- markPad (left, top, right, bottom). Returns the row, the title TextBlock and the mark
--- TextBlock, either of which is nil when that part failed to build.
---@param outer any
---@param name string
---@param opts table
---@return any row, any|nil title, any|nil mark
function M.HeaderRow(outer, name, opts)
    local sec = opts.sec
    local textSpec = sec.text or {}
    -- The size comes from the caller, because a fold header takes the hint size and a section
    -- header the section text size.
    local size = Paint.TextSize(opts.config, opts.themeSize, opts.fontKey)
    local row = Umg.Construct("/Script/UMG.HorizontalBox", outer, name)
    local tp = opts.titlePad
    local rule = sec.variant == "rule"

    -- A rule title takes its own width, so the line fills the rest of the row as in StyleLab.
    local titlePad = tp
    if rule then
        titlePad = { tp[1], tp[2], 10, tp[4] }
    end
    local title = TryPart("title", function()
        return AddRowText(row, name .. "_Title", Paint.Caption(opts.title, textSpec), size,
            textSpec.color or sec.color, textSpec, titlePad, not rule)
    end)

    if rule then
        TryPart("rule", function()
            local box = Umg.Construct("/Script/UMG.SizeBox", row, name .. "_RuleSize")
            local line = Paint.Box(box, name .. "_Rule", { fill = sec.line }, 0)
            pcall(function()
                box:SetHeightOverride(1)
                box:SetContent(line)
            end)
            local slot = row:AddChildToHorizontalBox(box)
            pcall(function()
                slot:SetSize({ SizeRule = 1, Value = 1.0 })
                slot:SetVerticalAlignment(V_CENTER)
                -- The line stops at the gap before the mark, or at the title's side padding with no mark.
                slot:SetPadding(Paint.Margin({ 0, 0, opts.mark ~= nil and tp[3] or tp[1], 0 }))
            end)
        end)
    end

    local mark = nil
    if opts.mark ~= nil then
        mark = TryPart("mark", function()
            local markBox = Umg.Construct("/Script/UMG.SizeBox", row, name .. "_MarkSize")
            local block = Umg.Construct("/Script/UMG.TextBlock", markBox, name .. "_Mark")
            Umg.StyleText(block, size, sec.mark, textSpec)
            Umg.SetLabelText(block, opts.mark)
            pcall(function()
                block:SetJustification(2)
            end)
            pcall(function()
                markBox:SetWidthOverride(18)
                markBox:SetContent(block)
            end)
            local slot = row:AddChildToHorizontalBox(markBox)
            pcall(function()
                slot:SetSize({ SizeRule = 0, Value = 0.0 })
                slot:SetHorizontalAlignment(H_RIGHT)
                slot:SetVerticalAlignment(V_CENTER)
                slot:SetPadding(Paint.Margin(opts.markPad))
            end)
            return block
        end)
    end
    return row, title, mark
end

--- Copy a state button's drawing fields onto a live control, so the control keeps its own kind
--- and fields while Paint.TrackPointer repaints it.
---@param ctrl table
---@param button table from Paint.StateButton
---@return table ctrl
function M.AdoptButton(ctrl, button)
    ctrl.widget = button.widget
    ctrl.root = button.root
    ctrl.fill = button.fill
    ctrl.flat = button.flat
    ctrl.stateColors = button.stateColors
    ctrl.lastState = button.lastState
    ctrl.shapes = button.shapes
    ctrl.shownKey = button.shownKey
    ctrl.edge = button.edge
    return ctrl
end

local function HeaderPads(spacing)
    local padX = spacing.sectionHeaderPadX
    local padY = spacing.sectionHeaderPadY
    -- The title carries the whole gap to the mark as its right padding, so the mark's left padding is 0.
    return { padX, padY, spacing.sectionHeaderGap, padY }, { 0, padY, padX, padY }
end

--- A section title for a section that does not fold. build.lua draws these; the stock variant is
--- the plain TextBlock it adds today, and the themed variants draw a label, a title with a rule,
--- or a filled bar.
---@param S table
---@param section table
---@param contentBox any
---@param suffix string
---@return any widget added to contentBox
function M.BuildTitle(S, section, contentBox, suffix)
    local config = S.config
    local name = string.format("ModMenu_Sec_%s_%s", section.id, suffix)
    local sec = M.ThemedSection(config)
    if sec == nil then
        local secTitle = Umg.Construct("/Script/UMG.TextBlock", contentBox, name)
        Umg.StyleText(secTitle, config.fontSection)
        Umg.SetLabelText(secTitle, M.TitleText(section))
        contentBox:AddChildToVerticalBox(secTitle)
        return secTitle
    end
    local titlePad = HeaderPads(config.spacing)
    -- A label or rule title sits on the panel, so it keeps no side padding of its own; a bar does.
    if sec.variant ~= "bar" then
        titlePad = { 0, titlePad[2], 0, titlePad[4] }
    end
    local host = contentBox
    local box = nil
    if sec.variant == "bar" then
        -- Without its band the title still shows, on the panel like a label title.
        box = TryPart("bar", function()
            return Paint.Box(contentBox, name .. "_Bar", { fill = sec.fill }, 0)
        end)
        host = box or contentBox
    end
    local row = M.HeaderRow(host, name .. "_Row", {
        config = config,
        sec = sec,
        title = M.TitleText(section),
        themeSize = (sec.text or {}).size,
        fontKey = "fontSection",
        titlePad = titlePad,
    })
    local widget = row
    if box ~= nil then
        pcall(function()
            box:SetContent(row)
        end)
        widget = box
    end
    local slot = contentBox:AddChildToVerticalBox(widget)
    Umg.FillVerticalSlot(slot)
    return widget
end

local function BuildThemedHeader(S, section, contentBox, name, collapsed, sec, palette)
    local titlePad, markPad = HeaderPads(S.config.spacing)
    local row, title, mark = M.HeaderRow(contentBox, name .. "_Row", {
        config = S.config,
        sec = sec,
        title = M.TitleText(section),
        mark = M.Mark(collapsed),
        themeSize = (sec.text or {}).size,
        fontKey = "fontSection",
        titlePad = titlePad,
        markPad = markPad,
    })
    local button = Paint.StateButton(contentBox, name, M.HeaderStates(sec, palette), row)
    local slot = contentBox:AddChildToVerticalBox(button.root)
    Umg.FillVerticalSlot(slot)
    local ctrl = M.AdoptButton({
        kind = "collapse",
        sectionId = section.id,
        label = title,
        mark = mark,
        body = nil,
        wasPressed = false,
    }, button)
    table.insert(S.liveControls, ctrl)
    return ctrl
end

--- Accordion header: title left, + / - right, full-width click target.
--- Caller attaches a body VerticalBox and always builds children into it.
---@return table ctrl
function M.BuildHeader(S, section, contentBox, suffix)
    local collapsed = M.IsCollapsed(S, section)
    local name = string.format("ModMenu_SecHdr_%s_%s", section.id, suffix)
    local sec, palette = M.ThemedSection(S.config)
    if sec ~= nil then
        return BuildThemedHeader(S, section, contentBox, name, collapsed, sec, palette)
    end
    local colors = Theme.Of(S.config)
    local fontSize = S.config.fontSection
    local titleText = M.TitleText(section)

    -- The Border is the visible fill, and the Button inside it is transparent (see Umg.SetFillColors).
    local fill = Umg.Construct("/Script/UMG.Border", contentBox, name .. "_Fill")
    local button = Umg.Construct("/Script/UMG.Button", fill, name .. "_Btn")
    local row = Umg.Construct("/Script/UMG.HorizontalBox", button, name .. "_Row")
    local spacing = S.config.spacing
    local title = AddHeaderText(row, name .. "_Title", titleText, fontSize, colors.textPrimary, true, spacing)
    local mark = AddHeaderText(row, name .. "_Mark", M.Mark(collapsed), fontSize, colors.sectionMark, false, spacing)

    pcall(function()
        button:SetContent(row)
        if button.SetClickMethod then
            button:SetClickMethod(1) -- MouseDown; matches other constructed buttons
        end
        fill:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        fill:SetContent(button)
    end)

    local slot = contentBox:AddChildToVerticalBox(fill)
    Umg.FillVerticalSlot(slot)
    local ctrl = {
        kind = "collapse",
        sectionId = section.id,
        widget = button,
        fill = fill,
        label = title,
        mark = mark,
        body = nil,
        wasPressed = false,
        -- The stock header is a recoloured Border, so Paint.TrackPointer repaints it as Umg.TrackPointer did.
        flat = true,
    }
    Umg.SetFill(ctrl, colors.sectionHeaderBg)
    table.insert(S.liveControls, ctrl)
    return ctrl
end

function M.AttachBody(ctrl, body, collapsed)
    if ctrl == nil or body == nil then
        return
    end
    ctrl.body = body
    SetBodyVisible(ctrl, collapsed)
end

return M
