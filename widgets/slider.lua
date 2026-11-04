--[[
  ModMenu widget: slider (a labelled track with a draggable knob over a numeric range)

  Layout: a header row with the label and the formatted value, then the engine's own Slider widget
  inside a SizeBox. The engine maps the pointer onto the track and captures the mouse during a drag,
  so the widget needs no geometry: in Funnel Runners every FGeometry a widget returns to Lua
  (GetCachedGeometry, GetTickSpaceGeometry, GetPaintSpaceGeometry) reads as an all-zero struct, so
  a widget that mapped the pointer itself could not tell where on the track the pointer was.

  Each poll reads the engine's value, snaps it to the item's step and stores it. onChange fires once
  when the engine releases the mouse and the value changed, or on every value change when live = true.
  pollClick consumes a click on the slider, so the shell does not treat it as a miss.
]]

local Theme = require("ModMenu.core.theme")

local Slider = {}
Slider.type = "slider"

-- These are the widget's own dimensions, not shell spacing tokens, like the number field's width.
local TRACK_HEIGHT = 18
local TRACK_HEIGHT_TOUCH = 36
local TRACK_WIDTH_IN_ROW = 160
local HEADER_GAP = 4
local ITEM_PAD = 8

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

-- This rounds half away from zero, the same rule the number widget uses.
local function RoundInteger(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function Clamp(n, item)
    if n < item.min then
        return item.min
    end
    if n > item.max then
        return item.max
    end
    return n
end

-- This snaps a number to the item's step, counted from min, then rounds an integer item and clamps.
-- The ends of the range are kept as they are, so max stays reachable when the range is not a whole
-- number of steps. Snapping goes through a fixed number of significant digits, so 0.1 steps do not
-- leave values such as 0.30000000000000004 in the store.
local function Snap(n, item)
    n = Clamp(n, item)
    local step = item.step
    if step ~= nil and n ~= item.min and n ~= item.max then
        n = item.min + RoundInteger((n - item.min) / step) * step
        n = tonumber(string.format("%.12g", n)) or n
    end
    if item.integer then
        n = RoundInteger(n)
    end
    return Clamp(n, item)
end

local function CoerceDefault(item)
    local n = tonumber(item.default)
    if n == nil then
        n = item.min
    end
    return Snap(n, item)
end

-- This turns a value from Set, seed or the pointer into a snapped number in range, or nil when it is not numeric.
-- A nil value resets the item to its default, as Set(nil) does on a number item.
local function Coerce(raw, item)
    if raw == nil then
        return CoerceDefault(item)
    end
    local n = tonumber(raw)
    if n == nil then
        return nil
    end
    return Snap(n, item)
end

-- This returns where a value sits on the track, from 0 at min to 1 at max.
local function Fraction(value, item)
    local n = tonumber(value) or item.min
    local f = (n - item.min) / (item.max - item.min)
    if f < 0 then
        return 0
    end
    if f > 1 then
        return 1
    end
    return f
end

-- This maps a track position from 0 to 1 back onto the range, snapped like any other value.
local function ValueAt(fraction, item)
    return Snap(item.min + fraction * (item.max - item.min), item)
end

-- A format string goes through string.format, and a format function receives the value and returns the text.
-- Without a format, an integer item prints as a whole number and any other value drops trailing zeros.
local function Format(value, item)
    local fmt = item.format
    if type(fmt) == "function" then
        local ok, text = pcall(fmt, value)
        if ok and text ~= nil then
            return tostring(text)
        end
    elseif type(fmt) == "string" then
        local ok, text = pcall(string.format, fmt, value)
        if ok then
            return text
        end
    end
    if item.integer then
        return tostring(RoundInteger(value))
    end
    local s = string.format("%.6f", value)
    s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return s
end

-- The spec runs without the game and cannot build a widget, so the module exposes these helpers.
Slider._coerce = Coerce
Slider._fraction = Fraction
Slider._valueAt = ValueAt
Slider._format = Format

function Slider.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if type(item.min) ~= "number" then
        error(prefix .. " min must be a number")
    end
    if type(item.max) ~= "number" then
        error(prefix .. " max must be a number")
    end
    if item.min >= item.max then
        error(prefix .. " min must be less than max")
    end
    if item.step ~= nil and (type(item.step) ~= "number" or item.step <= 0) then
        error(prefix .. " step must be a positive number")
    end
    if item.default ~= nil and tonumber(item.default) == nil then
        error(prefix .. " default must be numeric")
    end
    if item.integer ~= nil and type(item.integer) ~= "boolean" then
        error(prefix .. " integer must be a boolean")
    end
    if item.live ~= nil and type(item.live) ~= "boolean" then
        error(prefix .. " live must be a boolean")
    end
    if item.showValue ~= nil and type(item.showValue) ~= "boolean" then
        error(prefix .. " showValue must be a boolean")
    end
    if item.labelWidth ~= nil and (type(item.labelWidth) ~= "number" or item.labelWidth < 1) then
        error(prefix .. " labelWidth must be a positive number")
    end
    if item.format ~= nil and type(item.format) ~= "string" and type(item.format) ~= "function" then
        error(prefix .. " format must be a string or a function")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

function Slider.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    -- A Set before Register stores the caller's value as given, so seed coerces it here.
    -- A missing value and a value that is not numeric both become the item's default.
    local n = Coerce(values[vkey], item)
    if n == nil then
        n = CoerceDefault(item)
    end
    values[vkey] = n
end

local function IsTouch(ctx)
    return ctx.Input ~= nil and ctx.Input.IsTouch ~= nil and ctx.Input.IsTouch() == true
end

-- This writes the value to the engine slider and rewrites the value text. Each UMG call sits in
-- its own pcall, because the spec calls apply without the game and a failed setter must not skip
-- the rest. The engine value is recorded so the next poll does not read the write back as a drag.
local function Paint(ctrl, value)
    pcall(function()
        ctrl.slider:SetValue(value)
    end)
    ctrl.engineValue = value
    pcall(function()
        ctrl.valueText:SetText(FText(Format(value, ctrl.item)))
    end)
end

local function FireIfChanged(ctrl, ctx)
    local value = ctx.values[ctrl.valueKey]
    if value == ctrl.lastFired then
        return
    end
    ctrl.lastFired = value
    ctx.SafeCall(ctrl.item.onChange, value)
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

-- This reads the engine's value, snaps it and stores it when it moved to a new step. The engine
-- slider is never written here, because a SetValue during the drag fights the capture.
local function ReadEngine(ctrl, ctx)
    local ok, raw = pcall(function()
        return ctrl.slider:GetValue()
    end)
    local n = ok and ReadNumber(raw) or nil
    if n == nil or n == ctrl.engineValue then
        return
    end
    ctrl.engineValue = n
    local value = Snap(n, ctrl.item)
    if value == ctx.values[ctrl.valueKey] then
        return
    end
    ctx.values[ctrl.valueKey] = value
    ctrl.value = value
    pcall(function()
        ctrl.valueText:SetText(FText(Format(value, ctrl.item)))
    end)
    if ctrl.item.live then
        FireIfChanged(ctrl, ctx)
    end
end

local function HasCapture(widget)
    local ok, captured = pcall(function()
        return widget:HasMouseCapture()
    end)
    return ok and (captured == true or captured == 1)
end

function Slider.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local name = ctx.namePrefix
    local colors = Theme.Of(ctx.config)
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = Coerce(ctx.values[vkey], item)
    if current == nil then
        current = CoerceDefault(item)
    end
    ctx.values[vkey] = current

    local touch = IsTouch(ctx)
    local trackHeight = touch and TRACK_HEIGHT_TOUCH or TRACK_HEIGHT

    local root = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, name .. "_Slider")

    local header = umg.Construct("/Script/UMG.HorizontalBox", root, name .. "_Header")
    local label = umg.Construct("/Script/UMG.TextBlock", header, name .. "_Label")
    umg.StyleText(label, ctx.config.fontItem)
    umg.SetLabelText(label, item.label)
    local valueText = umg.Construct("/Script/UMG.TextBlock", header, name .. "_Value")
    umg.StyleText(valueText, ctx.config.fontItem, colors.textMuted)
    umg.SetLabelText(valueText, Format(current, item))
    -- labelWidth fixes the label column, as the number widget's does, and the readout takes the rest of the row.
    local labelHost = label
    local fixedLabel = type(item.labelWidth) == "number"
    if fixedLabel then
        labelHost = umg.Construct("/Script/UMG.SizeBox", header, name .. "_LabelSize")
        pcall(function()
            labelHost:SetWidthOverride(item.labelWidth)
            labelHost:SetContent(label)
        end)
    end
    pcall(function()
        local labelSlot = header:AddChildToHorizontalBox(labelHost)
        labelSlot:SetSize({ SizeRule = fixedLabel and 0 or 1, Value = fixedLabel and 0.0 or 1.0 })
        labelSlot:SetVerticalAlignment(2)
        local valueSlot = header:AddChildToHorizontalBox(valueText)
        valueSlot:SetSize({ SizeRule = fixedLabel and 1 or 0, Value = fixedLabel and 1.0 or 0.0 })
        valueSlot:SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
        valueSlot:SetVerticalAlignment(2)
    end)
    if item.showValue == false then
        pcall(function()
            valueText:SetVisibility(1)
        end)
    end
    pcall(function()
        local headerSlot = root:AddChildToVerticalBox(header)
        headerSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = HEADER_GAP })
    end)

    local size = umg.Construct("/Script/UMG.SizeBox", root, name .. "_TrackSize")
    pcall(function()
        size:SetHeightOverride(trackHeight)
        if ctx.layout == "horizontal" then
            size:SetWidthOverride(TRACK_WIDTH_IN_ROW)
        end
    end)
    -- MouseUsesStep is a plain property, not a setter, so the pcall covers a build without it.
    local slider = umg.Construct("/Script/UMG.Slider", size, name .. "_Track")
    pcall(function()
        slider:SetMinValue(item.min)
        slider:SetMaxValue(item.max)
        if item.step ~= nil then
            slider:SetStepSize(item.step)
            slider.MouseUsesStep = true
        end
        slider:SetValue(current)
        slider:SetSliderBarColor(colors.buttonBgPrimary or colors.textAccent)
        slider:SetSliderHandleColor(colors.textPrimary)
    end)
    pcall(function()
        size:SetContent(slider)
        root:AddChildToVerticalBox(size)
    end)

    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and item.fill == true,
    })
    umg.AddItemPad(ctx, name .. "_Pad", ITEM_PAD)

    table.insert(ctx.liveControls, {
        kind = "slider",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        slider = slider,
        valueText = valueText,
        valueKey = vkey,
        value = current,
        engineValue = current,
        dragging = false,
        lastFired = current,
        -- The slider takes no part in focus navigation yet. These stubs keep the control's shape uniform.
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    })
end

--- Read the engine's value on every tick. While the engine holds the mouse the drag is on, and
--- onChange fires once when the capture ends and the value changed. A click without a capture the
--- poll saw, such as a tap, fires at once on the next tick, because no release will follow.
function Slider.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.slider) then
        return
    end
    ReadEngine(ctrl, ctx)
    if HasCapture(ctrl.slider) then
        ctrl.dragging = true
        return
    end
    if ctrl.dragging then
        ctrl.dragging = false
        ctx.ReclaimMenuInput()
    end
    FireIfChanged(ctrl, ctx)
end

--- A click on the slider consumes the latch, so the shell does not count it as a miss. The value
--- itself comes from the engine on the next poll.
--- @return boolean true if click consumed
function Slider.pollClick(ctrl, ctx)
    if not ctx.IsValid(ctrl.slider) or not ctx.Input.WidgetHovered(ctrl.slider) then
        return false
    end
    ctx.Input.IgnoreClicks(2)
    return true
end

--- Set the value from the host. The value is coerced and stored, and onChange does not fire,
--- because the host supplied the value. The registry stores Set's raw value before it calls apply,
--- so a value that is not numeric puts the last good value back in the store.
function Slider.apply(ctrl, value, ctx)
    local n = Coerce(value, ctrl.item)
    if n == nil then
        if ctrl.value ~= nil then
            ctx.values[ctrl.valueKey] = ctrl.value
        end
        return
    end
    ctx.values[ctrl.valueKey] = n
    ctrl.value = n
    ctrl.lastFired = n
    Paint(ctrl, n)
end

return Slider
