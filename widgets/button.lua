--[[
  ModMenu widget: button

  Visual layers (disabled wins, then active, then variant):
    enabled = false  → themed disabled chrome + no clicks
    active = true    → "this is on" (green) — not a variant
    variant          → Bootstrap-like intent (primary/danger/warning/…)
    default          → theme buttonBg
    confirm          → optional table; onClick waits for the in-shell modal

  Hover and pressed sit below the disabled and active layers. Each poll reads IsHovered and
  IsPressed and repaints the fill from Theme.ButtonStates only when the state changes.
  A mouse click fires on release over the button; a touch tap fires on press.
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")

local Button = {}
Button.type = "button"

local VARIANTS = {
    default = true,
    primary = true,
    secondary = true,
    success = true,
    danger = true,
    warning = true,
    info = true,
}

-- Short-lived names from the first variant pass.
local ALIASES = {
    accent = "primary",
}

local VARIANT_CHROME = {
    primary = { "buttonBgPrimary", "buttonTextPrimary" },
    secondary = { "buttonBgSecondary", "buttonTextSecondary" },
    success = { "buttonBgSuccess", "buttonTextSuccess" },
    danger = { "buttonBgDanger", "buttonTextDanger" },
    warning = { "buttonBgWarning", "buttonTextWarning" },
    info = { "buttonBgInfo", "buttonTextInfo" },
}

local VARIANT_HELP = "default|primary|secondary|success|danger|warning|info"

function Button.NormalizeVariant(value)
    if value == nil or value == "" then
        return "default"
    end
    if type(value) ~= "string" then
        return nil
    end
    value = ALIASES[value] or value
    if VARIANTS[value] then
        return value
    end
    return nil
end

local function ChromeColors(colors, item)
    colors = colors or {}
    local fallbackBg, fallbackFg = colors.buttonBg, colors.buttonText
    if item.enabled == false then
        return colors.buttonBgDisabled or fallbackBg, colors.buttonTextDisabled or fallbackFg
    end
    if item.active == true then
        return colors.buttonBgActive or fallbackBg, colors.buttonTextActive or fallbackFg
    end
    local variant = item.variant or "default"
    local keys = VARIANT_CHROME[variant]
    if keys then
        return colors[keys[1]] or fallbackBg, colors[keys[2]] or fallbackFg
    end
    return fallbackBg, fallbackFg
end

--- Paint UMG from item.enabled / item.active / item.variant.
function Button.applyChrome(ctrl, ctx)
    if ctrl == nil or ctrl.item == nil then
        return
    end
    local item = ctrl.item
    local enabled = item.enabled ~= false
    ctrl.enabled = enabled
    local colors = Theme.Of(ctx and ctx.config)
    local bg, fg = ChromeColors(colors, item)
    -- This paints the resting fill, so the hover poll compares against the normal state from here.
    ctrl.lastState = "normal"
    -- Disabled and active buttons keep one fill in every pointer state.
    local hover, pressed = bg, bg
    if enabled and item.active ~= true then
        local states = Theme.ButtonStates(colors, item.variant)
        hover, pressed = states.hover, states.pressed
    end
    ctrl.stateColors = { normal = bg, hover = hover, pressed = pressed }
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetIsEnabled(enabled)
            -- Fully transparent, so UMG's stock grey hovered brush draws nothing; the Border
            -- behind the button carries every state colour (2026-11-04).
            ctrl.widget:SetBackgroundColor({ R = 1, G = 1, B = 1, A = 0 })
        end
        if ctrl.fill ~= nil then
            ctrl.fill:SetBrushColor(bg)
        end
    end)
    if ctrl.labelWidget ~= nil and ctx ~= nil and ctx.umg ~= nil then
        ctx.umg.StyleText(ctrl.labelWidget, ctx.config.fontItem, fg)
    end
end

function Button.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onClick ~= nil and type(item.onClick) ~= "function" then
        error(prefix .. " onClick must be a function")
    end
    if item.enabled ~= nil and type(item.enabled) ~= "boolean" then
        error(prefix .. " enabled must be a boolean")
    end
    if item.active ~= nil and type(item.active) ~= "boolean" then
        error(prefix .. " active must be a boolean")
    end
    if item.variant ~= nil and Button.NormalizeVariant(item.variant) == nil then
        error(prefix .. " variant must be " .. VARIANT_HELP)
    end
    if item.confirm ~= nil then
        if type(item.confirm) ~= "table" then
            error(prefix .. " confirm must be a table")
        end
        for _, key in ipairs({ "title", "message", "confirmLabel", "cancelLabel" }) do
            if item.confirm[key] ~= nil and type(item.confirm[key]) ~= "string" then
                error(prefix .. " confirm." .. key .. " must be a string")
            end
        end
        if item.confirm.variant ~= nil and Button.NormalizeVariant(item.confirm.variant) == nil then
            error(prefix .. " confirm.variant must be " .. VARIANT_HELP)
        end
        if item.onClick == nil then
            error(prefix .. " confirm requires onClick (runs after Confirm)")
        end
    end
end

function Button.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    item.variant = Button.NormalizeVariant(item.variant) or "default"
    local fill, button, label = umg.CreateFilledButton(ctx.contentBox, ctx.namePrefix, item.label)
    umg.AddToContent(ctx, fill)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    local ctrl = {
        kind = "button",
        sectionId = ctx.section.id,
        item = item,
        widget = button,
        fill = fill,
        labelWidget = label,
        enabled = item.enabled ~= false,
        wasPressed = false,
    }
    Button.applyChrome(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

--- Fire onClick. Shared by IsPressed poll and LMB-latch pollClick.
---@param path string
local function FireClick(ctrl, ctx, path)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    if ctrl.item.confirm ~= nil and ctx.ShowConfirm ~= nil then
        ctx.ShowConfirm(ctrl.item)
    else
        ctx.SafeCall(ctrl.item.onClick)
    end
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    -- Reclaim touches PlayerController / SetInputMode — must stay on the game thread.
    ExecuteInGameThreadWithDelay(200, Util.PinFn(function()
        ctx.ReclaimMenuInput()
    end))
    return true
end

local function IsTrue(value)
    return value == true or value == 1
end

--- Read the pointer state of the UButton as "pressed", "hover" or "normal".
local function PointerState(widget)
    local hovered, pressed = false, false
    pcall(function()
        hovered = IsTrue(widget:IsHovered())
    end)
    pcall(function()
        pressed = IsTrue(widget:IsPressed())
    end)
    if pressed then
        return "pressed"
    end
    if hovered then
        return "hover"
    end
    return "normal"
end

--- Repaint the Border behind the button when the pointer state changes.
local function PaintPointerState(ctrl)
    if ctrl.widget == nil or ctrl.item == nil or ctrl.item.active == true then
        return
    end
    local state = PointerState(ctrl.widget)
    if state == ctrl.lastState then
        return
    end
    ctrl.lastState = state
    local colors = ctrl.stateColors
    if colors ~= nil and ctrl.fill ~= nil then
        pcall(function()
            ctrl.fill:SetBrushColor(colors[state] or colors.normal)
        end)
    end
end

--- Continuous press poll. A mouse click fires when the button is released over it, so the
--- pressed colour stays visible while the button is held and dragging off cancels the click.
--- A touch tap has no held phase, so it fires on the press edge.
function Button.poll(ctrl, ctx)
    if ctrl.enabled == false then
        return
    end
    PaintPointerState(ctrl)
    if ctx.Input.IsTouch() then
        if ctx.Input.WidgetPressedEdge(ctrl, ctrl.widget) then
            FireClick(ctrl, ctx, "press-edge")
        end
        return
    end
    local down = ctx.Input.WidgetIsDown(ctrl.widget)
    if down then
        ctrl.holding = true
        ctrl.armTicks = 0
        return
    end
    if ctrl.holding then
        ctrl.holding = false
        ctrl.armed = false
        if ctx.Input.WidgetHovered(ctrl.widget) then
            FireClick(ctrl, ctx, "release")
        end
        return
    end
    -- The mouse-down latch can arrive a tick before IsPressed turns true. Give up on an armed
    -- press that never shows as held, so a stale latch cannot fire a later click.
    if ctrl.armed then
        ctrl.armTicks = (ctrl.armTicks or 0) + 1
        if ctrl.armTicks > 5 then
            ctrl.armed = false
        end
    end
end

--- The mouse-down latch claims a press on the hovered button without firing it; the release
--- in Button.poll fires. Touch fires here, as it did before.
--- @return boolean true if click consumed
function Button.pollClick(ctrl, ctx)
    if ctrl.enabled == false then
        return false
    end
    if not ctx.Input.WidgetHovered(ctrl.widget) then
        return false
    end
    if ctx.Input.IsTouch() then
        return FireClick(ctrl, ctx, "latch-hover")
    end
    ctrl.armed = true
    ctrl.armTicks = 0
    return true
end
return Button
