--[[
  ModMenu.shell.confirm — in-shell modal for destructive actions.

  Covers the docked panel (same canvas, higher Z). Blocks other widget polls
  while open. Cancel / close menu runs nothing. Confirm runs onConfirm once.
  A new Show replaces the current prompt (treated as Cancel).

  The card, dim and dividers draw from the resolved confirm style, and the two buttons from the
  button style. The dialog is built fresh on every Show, so each look is written before it is
  first shown.
]]

local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local Paint = require("ModMenu.core.paint")
local Theme = require("ModMenu.core.theme")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Dock = require("ModMenu.shell.dock")
local Button = require("ModMenu.widgets.button")
local Motion = require("ModMenu.core.motion")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local SafeCall = Util.SafeCall
local Construct = Umg.Construct
local StyleText = Umg.StyleText
local SetLabelText = Umg.SetLabelText
local EnableAutoWrap = Umg.EnableAutoWrap

local M = {}

local function Normalize(opts)
    if type(opts) ~= "table" then
        error("ModMenu.Confirm expects a table")
    end
    if type(opts.onConfirm) ~= "function" then
        error("ModMenu.Confirm requires onConfirm")
    end
    if opts.onCancel ~= nil and type(opts.onCancel) ~= "function" then
        error("ModMenu.Confirm onCancel must be a function")
    end
    local variant = Button.NormalizeVariant(opts.variant) or "danger"
    local title = opts.title
    if type(title) ~= "string" or title == "" then
        title = "Are you sure?"
    end
    local message = opts.message
    if type(message) ~= "string" or message == "" then
        message = nil
    end
    local confirmLabel = opts.confirmLabel
    if type(confirmLabel) ~= "string" or confirmLabel == "" then
        confirmLabel = "Confirm"
    end
    local cancelLabel = opts.cancelLabel
    if type(cancelLabel) ~= "string" or cancelLabel == "" then
        cancelLabel = "Cancel"
    end
    return {
        title = title,
        message = message,
        confirmLabel = confirmLabel,
        cancelLabel = cancelLabel,
        variant = variant,
        onConfirm = opts.onConfirm,
        onCancel = opts.onCancel,
    }
end

local function DestroyOverlay(S)
    if IsValid(S.confirmRoot) then
        pcall(function()
            S.confirmRoot:RemoveFromParent()
        end)
        pcall(function()
            S.confirmRoot:SetVisibility(1)
        end)
    end
    S.confirmRoot = nil
    S.confirmSlot = nil
    S.confirmControls = nil
end

--- Dismiss without stacking. reason = "confirm" | "cancel" | "close"
function M.Hide(S, reason)
    local spec = S.confirm
    S.confirm = nil
    DestroyOverlay(S)
    if spec == nil then
        return
    end
    if reason == "confirm" then
        Debug("Confirm accepted: " .. tostring(spec.title))
        SafeCall(spec.onConfirm)
    else
        Debug("Confirm dismissed (" .. tostring(reason) .. "): " .. tostring(spec.title))
        SafeCall(spec.onCancel)
    end
end

function M.IsOpen(S)
    return S.confirm ~= nil
end

local function AddHairline(parent, name, color)
    local box = Construct("/Script/UMG.SizeBox", parent, name)
    pcall(function()
        box:SetHeightOverride(1)
    end)
    local line = Construct("/Script/UMG.Border", box, name .. "_Line")
    pcall(function()
        line:SetBrushColor(color)
        line:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        box:SetContent(line)
    end)
    parent:AddChildToVerticalBox(box)
end

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local WHITE = { R = 1, G = 1, B = 1, A = 1 }

-- An underline role draws as ghost in the dialog, because its stacked bar belongs to the button
-- widget's own face and the dialog builds its buttons through Paint.StateButton alone.
local function GhostRoles(roles)
    local out = {}
    for name, role in pairs(roles or {}) do
        local copy = {}
        for k, v in pairs(role) do
            copy[k] = v
        end
        if copy.variant == "underline" then
            copy.variant = "ghost"
        end
        out[name] = copy
    end
    return out
end

--- The pointer looks and caption style of a confirm button for a role, built as button items are
--- built, from Button.States and Button.CaptionStyle, so a ghost theme or role outlines the dialog
--- buttons as it outlines button items. A flat fill button keeps the legacy hover and pressed
--- colours, so light and dark keep today's dialog.
---@param config table the menu instance's config
---@param variant string the button role, such as "danger" or "secondary"
---@return table states for Paint.StateButton
---@return table labelStyle { color, size, textSpec, pad }
function M.ButtonLook(config, variant)
    local resolved = config.resolved or {}
    local item = { variant = variant }
    local states = Button.States(resolved, item)
    if states.variant == "underline" then
        states = Button.States(resolved, item, { variant = "ghost", roles = GhostRoles(states.style.roles) })
    end
    if states.variant == "fill" and states.edge == nil and not Paint.NeedsShapes(states) then
        local roles = states.style.roles or {}
        local role = roles[Button.NormalizeVariant(variant) or "default"] or roles.default or {}
        local legacy = Theme.ButtonStates(Theme.Of(config), variant)
        states.hover = { fill = role.hover or legacy.hover, radius = states.hover.radius, pill = states.hover.pill }
        states.pressed = { fill = role.pressed or legacy.pressed, radius = states.pressed.radius,
            pill = states.pressed.pill }
    end
    local caption = Button.CaptionStyle({ config = config }, states)
    caption.pad = { 12, 4, 12, 4 }
    return states, caption
end

local function MakeButton(S, parent, namePrefix, label, variant, role)
    local states, labelStyle = M.ButtonLook(S.config, variant)
    local button = Paint.StateButton(parent, namePrefix, states, label, labelStyle)
    -- The live entry keeps its confirm kind and fields; the button fields come from the state button.
    button.kind = "confirm"
    button.role = role
    button.labelWidget = button.label
    button.item = { variant = variant, enabled = true, label = label }
    button.wasPressed = false
    return button
end

local function BuildOverlay(S, spec)
    if not IsValid(S.menuCanvas) then
        Log("Confirm: no menu canvas")
        return false
    end

    S.confirmGen = (S.confirmGen or 0) + 1
    local suffix = tostring(S.confirmGen)
    local colors = Theme.Of(S.config)
    local canvas = S.menuCanvas
    local resolved = S.config.resolved or {}
    local look = resolved.confirm or {}
    local panel = resolved.panel or {}
    local dimColor = look.dim or colors.overlayDim or { R = 0, G = 0, B = 0, A = 0.55 }
    local cardColor = look.fill or colors.confirmCardBg or colors.panelBg

    -- Dim fills the docked panel. The card is a separate auto-sized child so
    -- height follows title + message + buttons (Bootstrap-style), not the panel.
    -- On a rounded panel the dim takes the panel's corners, and it stops short of the panel's
    -- shadow by the shadow's depth, so it covers the panel body and nothing outside it. A square
    -- panel with no shadow keeps the single flat Border it always had.
    local panelShape = { fill = dimColor, radius = panel.radius, pill = false }
    local shadowDepth = Paint.ShadowDepth(panel)
    local root, dim
    if Paint.IsFlat(panelShape) and shadowDepth <= 0 then
        dim = Construct("/Script/UMG.Border", canvas, "ModMenu_ConfirmDim_" .. suffix)
        pcall(function()
            dim:SetBrushColor(dimColor)
            dim:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        end)
        root = dim
    else
        root = Paint.Box(canvas, "ModMenu_ConfirmHost_" .. suffix, { fill = Alpha(WHITE, 0) },
            { 0, 0, shadowDepth, shadowDepth })
        dim = Paint.Box(root, "ModMenu_ConfirmDim_" .. suffix, panelShape, 0)
        pcall(function()
            root:SetContent(dim)
        end)
    end

    local inner = Construct("/Script/UMG.CanvasPanel", dim, "ModMenu_ConfirmInner_" .. suffix)
    pcall(function()
        dim:SetContent(inner)
    end)

    -- The card width is read per build from this instance's config, because each menu instance has its own spacing.
    local cardWidth = S.config.spacing.confirmWidth
    local sizeBox = Construct("/Script/UMG.SizeBox", inner, "ModMenu_ConfirmSize_" .. suffix)
    pcall(function()
        sizeBox:SetWidthOverride(cardWidth)
        if sizeBox.SetMaxDesiredWidth then
            sizeBox:SetMaxDesiredWidth(cardWidth)
        end
    end)

    -- A flat card is the recoloured Border it always was; a rounded card is written into its own
    -- brush before the dialog is first shown, and is never recoloured (field note 30).
    local card = Paint.Box(sizeBox, "ModMenu_ConfirmCard_" .. suffix, { fill = cardColor, radius = look.radius }, 0)
    pcall(function()
        sizeBox:SetContent(card)
    end)

    local vbox = Construct("/Script/UMG.VerticalBox", card, "ModMenu_ConfirmBox_" .. suffix)
    pcall(function()
        card:SetContent(vbox)
    end)

    local sectionPad = { Left = 16, Top = 12, Right = 16, Bottom = 12 }
    local divider = look.divider or colors.confirmDivider or colors.panelBorder

    local title = Construct("/Script/UMG.TextBlock", vbox, "ModMenu_ConfirmTitle_" .. suffix)
    StyleText(title, S.config.fontSection, colors.textPrimary)
    SetLabelText(title, spec.title)
    EnableAutoWrap(title)
    local titleSlot = vbox:AddChildToVerticalBox(title)
    pcall(function()
        titleSlot:SetPadding(sectionPad)
        titleSlot:SetHorizontalAlignment(0)
        titleSlot:SetSize({ SizeRule = 0, Value = 0.0 })
    end)

    AddHairline(vbox, "ModMenu_ConfirmRule1_" .. suffix, divider)

    if spec.message ~= nil then
        local msg = Construct("/Script/UMG.TextBlock", vbox, "ModMenu_ConfirmMsg_" .. suffix)
        StyleText(msg, S.config.fontItem, colors.textMuted)
        SetLabelText(msg, spec.message)
        EnableAutoWrap(msg)
        local msgSlot = vbox:AddChildToVerticalBox(msg)
        pcall(function()
            msgSlot:SetPadding(sectionPad)
            msgSlot:SetHorizontalAlignment(0)
            msgSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        end)
        AddHairline(vbox, "ModMenu_ConfirmRule2_" .. suffix, divider)
    end

    local row = Construct("/Script/UMG.HorizontalBox", vbox, "ModMenu_ConfirmRow_" .. suffix)
    local rowSlot = vbox:AddChildToVerticalBox(row)
    pcall(function()
        rowSlot:SetPadding({ Left = 12, Top = 10, Right = 12, Bottom = 10 })
        rowSlot:SetSize({ SizeRule = 0, Value = 0.0 })
    end)

    local push = Construct("/Script/UMG.Spacer", row, "ModMenu_ConfirmPush_" .. suffix)
    local pushSlot = row:AddChildToHorizontalBox(push)
    pcall(function()
        pushSlot:SetSize({ SizeRule = 1, Value = 1.0 })
    end)

    local cancel = MakeButton(S, row, "ModMenu_ConfirmNo_" .. suffix, spec.cancelLabel, "secondary", "cancel")
    local cancelSlot = row:AddChildToHorizontalBox(cancel.root)
    pcall(function()
        cancelSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        cancelSlot:SetPadding({ Left = 0, Top = 0, Right = S.config.spacing.confirmGap, Bottom = 0 })
        cancelSlot:SetVerticalAlignment(2)
    end)

    local ok = MakeButton(S, row, "ModMenu_ConfirmYes_" .. suffix, spec.confirmLabel, spec.variant, "confirm")
    local okSlot = row:AddChildToHorizontalBox(ok.root)
    pcall(function()
        okSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        okSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        okSlot:SetVerticalAlignment(2)
    end)

    local cardSlot = inner:AddChildToCanvas(sizeBox)
    pcall(function()
        cardSlot:SetAutoSize(true)
        cardSlot:SetAnchors({
            Minimum = { X = 0.5, Y = 0.5 },
            Maximum = { X = 0.5, Y = 0.5 },
        })
        cardSlot:SetAlignment({ X = 0.5, Y = 0.5 })
        cardSlot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        cardSlot:SetZOrder(1)
    end)

    local slot = canvas:AddChildToCanvas(root)
    Dock.ApplyPercentLayout(slot, S.config)
    pcall(function()
        slot:SetZOrder(20)
    end)

    S.confirmRoot = root
    S.confirmSlot = slot
    S.confirmControls = { cancel, ok }
    return true
end

function M.Show(S, opts)
    local spec = Normalize(opts)
    if M.IsOpen(S) then
        M.Hide(S, "cancel")
    end
    if not IsValid(S.menuCanvas) or S.menuOpen ~= true then
        Log("Confirm: menu is not open")
        return false
    end
    if not BuildOverlay(S, spec) then
        return false
    end
    S.confirm = spec
    Input.ClearClickState()
    Input.IgnoreClicks(2)
    InputMode.Reclaim()
    Debug("Confirm shown: " .. spec.title)
    return true
end

--- Poll only the modal buttons. Consumes leftover clicks so they cannot hit the panel.
---@return boolean true if a confirm is open
function M.Poll(S)
    if S.confirm == nil then
        return false
    end

    local fired = nil
    for _, ctrl in ipairs(S.confirmControls or {}) do
        Paint.TrackPointer(ctrl)
        if Input.ReleaseClick(ctrl, ctrl.widget) then
            Input.DebugClick("release", ctrl, ctrl.widget)
            fired = ctrl.role
            Input.SuppressPressEdge(ctrl)
            break
        end
    end

    if Input.ConsumeMouseClick() and fired == nil then
        local latchHit = false
        for _, ctrl in ipairs(S.confirmControls or {}) do
            local consumed, fireNow = Input.ArmClick(ctrl, ctrl.widget)
            if consumed then
                if fireNow then
                    Input.DebugClick("latch-hover", ctrl, ctrl.widget)
                    fired = ctrl.role
                    Input.SuppressPressEdge(ctrl)
                end
                latchHit = true
                break
            end
        end
        if not latchHit then
            Input.DebugClick("latch-miss", { kind = "confirm" }, nil)
        end
    end

    if fired == "confirm" then
        Input.IgnoreClicks(2)
        -- The variant is read first, because Hide clears the spec. A danger confirm shakes the menu.
        if S.confirm.variant == "danger" then
            Motion.Shake(S)
        else
            Motion.Pop(S)
        end
        M.Hide(S, "confirm")
        InputMode.Reclaim()
    elseif fired == "cancel" then
        Input.IgnoreClicks(2)
        Motion.Pop(S)
        M.Hide(S, "cancel")
        InputMode.Reclaim()
    end
    return true
end

--- Button item.confirm → Show. onClick runs only after Confirm.
function M.FromButton(S, item)
    local spec = item.confirm
    if type(spec) ~= "table" then
        return false
    end
    M.Show(S, {
        title = spec.title,
        message = spec.message,
        confirmLabel = spec.confirmLabel,
        cancelLabel = spec.cancelLabel,
        variant = spec.variant or item.variant,
        onConfirm = item.onClick,
    })
    return true
end

return M
