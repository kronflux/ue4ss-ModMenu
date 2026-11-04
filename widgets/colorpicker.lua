--[[
  ModMenu widget: colorpicker

  Layout: a caption, a swatch filled with the current colour, and one labelled slider per channel
  (R, G, B and, unless alpha is false, A), each from 0 to 1 in steps of 0.01 with its number shown.
  The sliders are the engine's own Slider widget, as the slider widget uses, so the engine maps the
  pointer onto the track and the widget reads no geometry: every FGeometry a widget returns to Lua in
  Funnel Runners reads as an all-zero struct.

  The value is a table { R, G, B, A }, each channel from 0 to 1. Each poll reads every engine slider,
  snaps it to a hundredth, stores the colour and repaints the swatch. onChange fires once when the
  engine releases the mouse and the colour changed, as the slider widget's does without live.

  The group's height is several rows, so a row cannot hold a colorpicker. A fold can.
]]

local Theme = require("ModMenu.core.theme")

local Colorpicker = {}
Colorpicker.type = "colorpicker"

-- These are the widget's own dimensions, not shell spacing tokens, like the slider's track height.
local TRACK_HEIGHT = 18
local TRACK_HEIGHT_TOUCH = 36
local SWATCH_HEIGHT = 24
local CHANNEL_LABEL_WIDTH = 16
local VALUE_WIDTH = 40
local ROW_GAP = 4
local ITEM_PAD = 8
local STEP = 0.01
-- Far above a single-precision read-back error and far below half a step.
local ENGINE_TOLERANCE = 1e-4

local ALL_CHANNELS = { "R", "G", "B", "A" }

-- The slider bar takes the channel's own hue, so the three colour sliders read at a glance.
local CHANNEL_TINT = {
    R = { R = 0.9, G = 0.25, B = 0.25, A = 1 },
    G = { R = 0.3, G = 0.8, B = 0.3, A = 1 },
    B = { R = 0.3, G = 0.5, B = 1, A = 1 },
}

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

local function Clamp01(n)
    if n < 0 then
        return 0
    end
    if n > 1 then
        return 1
    end
    return n
end

-- A channel that is missing or not a number is 0, except alpha, which is opaque.
local function ChannelValue(raw, key)
    local n = type(raw) == "number" and raw == raw and raw or nil
    if n == nil then
        return key == "A" and 1 or 0
    end
    return Clamp01(n)
end

--- Return a new { R, G, B, A } table with every channel clamped to 0..1, A held at 1 when the item
--- has alpha = false, and nil for a value that is not a table.
---@param color any
---@param item table
---@return table|nil
function Colorpicker._coerce(color, item)
    if type(color) ~= "table" then
        return nil
    end
    local result = {}
    for _, key in ipairs(ALL_CHANNELS) do
        result[key] = ChannelValue(color[key], key)
    end
    if item ~= nil and item.alpha == false then
        result.A = 1
    end
    return result
end

--- The channels the item shows a slider for, in order.
---@param item table
---@return string[]
function Colorpicker._channels(item)
    if item ~= nil and item.alpha == false then
        return { "R", "G", "B" }
    end
    return { "R", "G", "B", "A" }
end

--- Snap a slider position to a hundredth and clamp it to 0..1.
---@param n number
---@return number
function Colorpicker._snap(n)
    return Clamp01(tonumber(string.format("%.2f", n)) or 0)
end

--- The text shown beside a channel slider.
---@param n number
---@return string
function Colorpicker._format(n)
    return string.format("%.2f", n)
end

--- The item's default colour, or opaque white when it has none.
---@param item table
---@return table
function Colorpicker._default(item)
    return Colorpicker._coerce(item.default, item) or Colorpicker._coerce({ R = 1, G = 1, B = 1, A = 1 }, item)
end

local function SameColor(a, b)
    if a == nil or b == nil then
        return a == b
    end
    for _, key in ipairs(ALL_CHANNELS) do
        if a[key] ~= b[key] then
            return false
        end
    end
    return true
end

local function CopyColor(color)
    return { R = color.R, G = color.G, B = color.B, A = color.A }
end

function Colorpicker.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.default ~= nil then
        if type(item.default) ~= "table" then
            error(prefix .. " default must be a table with R, G, B and A")
        end
        for _, key in ipairs(ALL_CHANNELS) do
            if item.default[key] == nil then
                error(prefix .. " default must be a table with R, G, B and A")
            end
        end
        for _, key in ipairs(ALL_CHANNELS) do
            local n = item.default[key]
            if type(n) ~= "number" or n ~= n or n < 0 or n > 1 then
                error(prefix .. " default." .. key .. " must be a number from 0 to 1")
            end
        end
    end
    if item.alpha ~= nil and type(item.alpha) ~= "boolean" then
        error(prefix .. " alpha must be a boolean")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

--- Store the default, and replace a value set before Register with its coerced form, so the stored
--- value is always a complete colour inside the range.
function Colorpicker.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    values[vkey] = Colorpicker._coerce(values[vkey], item) or Colorpicker._default(item)
end

local function IsTouch(ctx)
    return ctx.Input ~= nil and ctx.Input.IsTouch ~= nil and ctx.Input.IsTouch() == true
end

-- Each UMG call sits in its own pcall, because the spec calls these without the game and a failed
-- setter must not skip the rest.
local function PaintSwatch(ctrl, color)
    pcall(function()
        ctrl.swatch:SetBrushColor(color)
    end)
end

local function PaintReadout(channel, n)
    pcall(function()
        channel.valueText:SetText(FText(Colorpicker._format(n)))
    end)
end

-- This writes a colour to the engine sliders, the readouts and the swatch. The engine value is
-- recorded so the next poll does not read the write back as a drag.
local function Paint(ctrl, color)
    for _, channel in ipairs(ctrl.channels) do
        local n = color[channel.key]
        pcall(function()
            channel.slider:SetValue(n)
        end)
        channel.engineValue = n
        PaintReadout(channel, n)
    end
    PaintSwatch(ctrl, color)
end

-- UE4SS returns a float property as a number or as userdata; tonumber covers both.
local function ReadNumber(v)
    if type(v) == "number" then
        return v
    end
    local ok, n = pcall(tonumber, v)
    if ok and type(n) == "number" then
        return n
    end
    return nil
end

local function HasCapture(widget)
    local ok, captured = pcall(function()
        return widget:HasMouseCapture()
    end)
    return ok and (captured == true or captured == 1)
end

-- This reads one engine slider and, when it moved to a new hundredth, stores the colour with that
-- channel changed and repaints the swatch. The engine slider is never written here, because a
-- SetValue during the drag fights the capture.
local function ReadEngine(ctrl, channel, ctx)
    local ok, raw = pcall(function()
        return channel.slider:GetValue()
    end)
    local n = ok and ReadNumber(raw) or nil
    if n == nil or n ~= n then
        return
    end
    -- The engine keeps a single-precision float, so a value Paint wrote reads back with a tiny error.
    -- Only a move larger than that error is a drag; the smallest real move is half a hundredth.
    if channel.engineValue ~= nil and math.abs(n - channel.engineValue) < ENGINE_TOLERANCE then
        return
    end
    channel.engineValue = n
    local snapped = Colorpicker._snap(n)
    local color = Colorpicker._coerce(ctx.values[ctrl.valueKey], ctrl.item) or Colorpicker._coerce(ctrl.value, ctrl.item)
    if color == nil or color[channel.key] == snapped then
        return
    end
    color[channel.key] = snapped
    ctx.values[ctrl.valueKey] = color
    ctrl.value = color
    PaintReadout(channel, snapped)
    PaintSwatch(ctrl, color)
end

local function FireIfChanged(ctrl, ctx)
    local color = ctx.values[ctrl.valueKey]
    if type(color) ~= "table" or SameColor(color, ctrl.lastFired) then
        return
    end
    ctrl.lastFired = CopyColor(color)
    ctx.SafeCall(ctrl.item.onChange, CopyColor(color))
end

function Colorpicker.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local name = ctx.namePrefix
    local colors = Theme.Of(ctx.config)
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = Colorpicker._coerce(ctx.values[vkey], item) or Colorpicker._default(item)
    ctx.values[vkey] = current

    local trackHeight = IsTouch(ctx) and TRACK_HEIGHT_TOUCH or TRACK_HEIGHT

    local root = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, name .. "_Color")
    local caption = umg.Construct("/Script/UMG.TextBlock", root, name .. "_Cap")
    umg.StyleText(caption, ctx.config.fontItem)
    umg.SetLabelText(caption, item.label)
    pcall(function()
        local slot = root:AddChildToVerticalBox(caption)
        slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = ROW_GAP })
    end)

    local swatchSize = umg.Construct("/Script/UMG.SizeBox", root, name .. "_SwatchSize")
    local swatch = umg.Construct("/Script/UMG.Border", swatchSize, name .. "_Swatch")
    pcall(function()
        swatch:SetBrushColor(current)
    end)
    pcall(function()
        swatchSize:SetHeightOverride(SWATCH_HEIGHT)
        swatchSize:SetContent(swatch)
        local slot = root:AddChildToVerticalBox(swatchSize)
        slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = ROW_GAP })
    end)

    local channels = {}
    for _, key in ipairs(Colorpicker._channels(item)) do
        local row = umg.Construct("/Script/UMG.HorizontalBox", root, name .. "_Row" .. key)

        local label = umg.Construct("/Script/UMG.TextBlock", row, name .. "_Label" .. key)
        umg.StyleText(label, ctx.config.fontItem, colors.textMuted)
        umg.SetLabelText(label, key)
        local labelSize = umg.Construct("/Script/UMG.SizeBox", row, name .. "_LabelSize" .. key)
        pcall(function()
            labelSize:SetWidthOverride(CHANNEL_LABEL_WIDTH)
            labelSize:SetContent(label)
            local slot = row:AddChildToHorizontalBox(labelSize)
            slot:SetSize({ SizeRule = 0, Value = 0.0 })
            slot:SetVerticalAlignment(2)
        end)

        local trackSize = umg.Construct("/Script/UMG.SizeBox", row, name .. "_TrackSize" .. key)
        pcall(function()
            trackSize:SetHeightOverride(trackHeight)
        end)
        local slider = umg.Construct("/Script/UMG.Slider", trackSize, name .. "_Track" .. key)
        pcall(function()
            slider:SetMinValue(0)
            slider:SetMaxValue(1)
            slider:SetStepSize(STEP)
            slider.MouseUsesStep = true
            slider:SetValue(current[key])
            slider:SetSliderBarColor(CHANNEL_TINT[key] or colors.buttonBgPrimary or colors.textAccent)
            slider:SetSliderHandleColor(colors.textPrimary)
        end)
        pcall(function()
            trackSize:SetContent(slider)
            local slot = row:AddChildToHorizontalBox(trackSize)
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetPadding({ Left = 4, Top = 0, Right = 4, Bottom = 0 })
            slot:SetVerticalAlignment(2)
        end)

        local valueText = umg.Construct("/Script/UMG.TextBlock", row, name .. "_Value" .. key)
        umg.StyleText(valueText, ctx.config.fontItem, colors.textMuted)
        umg.SetLabelText(valueText, Colorpicker._format(current[key]))
        local valueSize = umg.Construct("/Script/UMG.SizeBox", row, name .. "_ValueSize" .. key)
        pcall(function()
            valueSize:SetWidthOverride(VALUE_WIDTH)
            valueSize:SetContent(valueText)
            local slot = row:AddChildToHorizontalBox(valueSize)
            slot:SetSize({ SizeRule = 0, Value = 0.0 })
            slot:SetVerticalAlignment(2)
        end)

        pcall(function()
            local slot = root:AddChildToVerticalBox(row)
            slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = ROW_GAP })
        end)
        channels[#channels + 1] = {
            key = key,
            slider = slider,
            valueText = valueText,
            engineValue = current[key],
        }
    end

    umg.AddToContent(ctx, root)
    umg.AddItemPad(ctx, name .. "_Pad", ITEM_PAD)

    table.insert(ctx.liveControls, {
        kind = "colorpicker",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        swatch = swatch,
        channels = channels,
        valueKey = vkey,
        value = current,
        dragging = false,
        lastFired = CopyColor(current),
        -- The colour picker takes no part in focus navigation yet. These stubs keep the control's shape uniform.
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    })
end

--- Read every engine slider on each tick. While the engine holds the mouse on any of them the drag
--- is on, and onChange fires once when the capture ends and the colour changed. A change without a
--- capture the poll saw, such as a tap, fires on the next tick, because no release will follow.
function Colorpicker.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget or ctrl.swatch or ctrl.channels[1].slider) then
        return
    end
    local captured = false
    for _, channel in ipairs(ctrl.channels) do
        if ctx.IsValid(channel.slider) then
            ReadEngine(ctrl, channel, ctx)
            if HasCapture(channel.slider) then
                captured = true
            end
        end
    end
    if captured then
        ctrl.dragging = true
        return
    end
    if ctrl.dragging then
        ctrl.dragging = false
        ctx.ReclaimMenuInput()
    end
    FireIfChanged(ctrl, ctx)
end

--- A click on a slider consumes the latch, so the shell does not count it as a miss. The value
--- itself comes from the engine on the next poll.
--- @return boolean true if click consumed
function Colorpicker.pollClick(ctrl, ctx)
    for _, channel in ipairs(ctrl.channels) do
        if ctx.IsValid(channel.slider) and ctx.Input.WidgetHovered(channel.slider) then
            ctx.Input.IgnoreClicks(2)
            return true
        end
    end
    return false
end

--- Set the colour from the host. The colour is coerced and stored, and onChange does not fire,
--- because the host supplied the value. The registry stores Set's value before it calls apply, so a
--- value that is not a table puts the last good colour back in the store.
function Colorpicker.apply(ctrl, value, ctx)
    local color = Colorpicker._coerce(value, ctrl.item)
    if color == nil then
        if ctrl.value ~= nil then
            ctx.values[ctrl.valueKey] = CopyColor(ctrl.value)
        end
        return
    end
    ctx.values[ctrl.valueKey] = color
    ctrl.value = color
    ctrl.lastFired = CopyColor(color)
    Paint(ctrl, color)
end

return Colorpicker
