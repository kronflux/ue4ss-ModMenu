--[[
  ModMenu widget: progress (a label, a bar and a readout on one line)

  The bar is the engine's own ProgressBar, filled to the value's place in the range min to max.
  It has no input and no onChange, and the value is not saved, because the host drives it with
  ModMenu.SetValue. SetValue moves the bar in place, with no rebuild. The fill colour follows the
  item's button variant, and the readout shows the percent of the range unless the item has a format.
]]

local Theme = require("ModMenu.core.theme")
local Button = require("ModMenu.widgets.button")

local Progress = {}
Progress.type = "progress"

-- These are the widget's own dimensions, not shell spacing tokens, like the number field's width.
local BAR_WIDTH = 200
local BAR_HEIGHT = 14
local READOUT_WIDTH = 56
local GAP = 8
local ITEM_PAD = 8

local DEFAULT_MIN = 0
local DEFAULT_MAX = 1

-- The theme key each variant paints the bar with. The default variant and an unset one use the accent.
local VARIANT_FILL = {
    primary = "buttonBgPrimary",
    secondary = "buttonBgSecondary",
    success = "buttonBgSuccess",
    danger = "buttonBgDanger",
    warning = "buttonBgWarning",
    info = "buttonBgInfo",
}

local VARIANT_HELP = "default|primary|secondary|success|danger|warning|info"

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

-- This rounds half away from zero, the same rule the number and slider widgets use.
local function RoundInteger(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

local function RangeOf(item)
    return item.min or DEFAULT_MIN, item.max or DEFAULT_MAX
end

local function Clamp(n, item)
    local low, high = RangeOf(item)
    if n < low then
        return low
    end
    if n > high then
        return high
    end
    return n
end

-- This turns a value from SetValue, Set or seed into a number inside the range, or nil when it is not numeric.
-- A nil value is not a number, so only the seed resets an item to its default.
local function Coerce(raw, item)
    local n = tonumber(raw)
    if n == nil then
        return nil
    end
    return Clamp(n, item)
end

local function CoerceDefault(item)
    local n = tonumber(item.default)
    if n == nil then
        n = (RangeOf(item))
    end
    return Clamp(n, item)
end

-- This returns where a value sits in the range, from 0 at min to 1 at max.
local function Fraction(value, item)
    local low, high = RangeOf(item)
    local n = tonumber(value) or low
    local f = (n - low) / (high - low)
    if f < 0 then
        return 0
    end
    if f > 1 then
        return 1
    end
    return f
end

local function Percent(value, item)
    return string.format("%d%%", RoundInteger(Fraction(value, item) * 100))
end

-- A format string goes through string.format, and a format function receives the value and returns the text.
-- A format that fails falls back to the percent, so a bad format never blanks the readout.
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
    return Percent(value, item)
end

-- This picks the fill colour for an item's variant. A variant the theme has no colour for uses the accent.
local function FillColor(item, colors)
    local variant = Button.NormalizeVariant(item.variant) or "default"
    local key = VARIANT_FILL[variant] or "buttonBgPrimary"
    return colors[key] or colors.buttonBgPrimary or colors.textAccent
end

-- The spec runs without the game and cannot build a widget, so the module exposes these helpers.
Progress._coerce = Coerce
Progress._fraction = Fraction
Progress._format = Format
Progress._fillColor = FillColor

function Progress.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.min ~= nil and type(item.min) ~= "number" then
        error(prefix .. " min must be a number")
    end
    if item.max ~= nil and type(item.max) ~= "number" then
        error(prefix .. " max must be a number")
    end
    local low, high = RangeOf(item)
    if low >= high then
        error(prefix .. " min must be less than max")
    end
    if item.default ~= nil and tonumber(item.default) == nil then
        error(prefix .. " default must be numeric")
    end
    if item.format ~= nil and type(item.format) ~= "string" and type(item.format) ~= "function" then
        error(prefix .. " format must be a string or a function")
    end
    if item.variant ~= nil and Button.NormalizeVariant(item.variant) == nil then
        error(prefix .. " variant must be " .. VARIANT_HELP)
    end
end

function Progress.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    -- A SetValue before Register stores the caller's value as given, so seed coerces it here.
    -- A missing value and a value that is not numeric both become the item's default.
    local n = Coerce(values[vkey], item)
    if n == nil then
        n = CoerceDefault(item)
    end
    values[vkey] = n
end

-- Each UMG call sits in its own pcall, because the spec calls apply without the game and a failed
-- setter must not skip the rest.
local function Paint(ctrl, value)
    pcall(function()
        ctrl.bar:SetPercent(Fraction(value, ctrl.item))
    end)
    pcall(function()
        ctrl.readout:SetText(FText(Format(value, ctrl.item)))
    end)
end

function Progress.build(ctx)
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

    local root = umg.Construct("/Script/UMG.HorizontalBox", ctx.contentBox, name .. "_Progress")
    local label = umg.Construct("/Script/UMG.TextBlock", root, name .. "_Label")
    umg.StyleText(label, ctx.config.fontItem)
    umg.SetLabelText(label, item.label)
    pcall(function()
        local slot = root:AddChildToHorizontalBox(label)
        slot:SetSize({ SizeRule = 1, Value = 1.0 })
        slot:SetVerticalAlignment(2)
    end)

    -- The size box gives the bar a fixed width and height, because a ProgressBar has no desired size of its own.
    local size = umg.Construct("/Script/UMG.SizeBox", root, name .. "_BarSize")
    local bar = umg.Construct("/Script/UMG.ProgressBar", size, name .. "_Bar")
    pcall(function()
        bar:SetFillColorAndOpacity(FillColor(item, colors))
    end)
    pcall(function()
        bar:SetPercent(Fraction(current, item))
    end)
    pcall(function()
        size:SetWidthOverride(BAR_WIDTH)
        size:SetHeightOverride(BAR_HEIGHT)
        size:SetContent(bar)
        local slot = root:AddChildToHorizontalBox(size)
        slot:SetSize({ SizeRule = 0, Value = 0.0 })
        slot:SetPadding({ Left = GAP, Top = 0, Right = 0, Bottom = 0 })
        slot:SetVerticalAlignment(2)
    end)

    local readoutSize = umg.Construct("/Script/UMG.SizeBox", root, name .. "_ReadoutSize")
    local readout = umg.Construct("/Script/UMG.TextBlock", readoutSize, name .. "_Readout")
    umg.StyleText(readout, ctx.config.fontItem, colors.textMuted)
    umg.SetLabelText(readout, Format(current, item))
    pcall(function()
        readoutSize:SetWidthOverride(READOUT_WIDTH)
        readoutSize:SetContent(readout)
        readout:SetJustification(2)
        local slot = root:AddChildToHorizontalBox(readoutSize)
        slot:SetSize({ SizeRule = 0, Value = 0.0 })
        slot:SetPadding({ Left = GAP, Top = 0, Right = 0, Bottom = 0 })
        slot:SetVerticalAlignment(2)
    end)

    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and item.fill == true,
    })
    umg.AddItemPad(ctx, name .. "_Pad", ITEM_PAD)

    table.insert(ctx.liveControls, {
        kind = "progress",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        bar = bar,
        readout = readout,
        labelWidget = label,
        valueKey = vkey,
        value = current,
        -- The bar takes no part in focus navigation. These stubs keep the control's shape uniform.
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    })
end

-- The bar has no input, so there is nothing to read each tick. The shell still calls poll on
-- every live control, and a control whose widget is gone must not raise.
function Progress.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
end

--- Set the value from the host. The value is clamped and stored, and the bar moves in place.
--- The registry stores the raw value before it calls apply, so a value that is not numeric
--- puts the last good value back in the store.
function Progress.apply(ctrl, value, ctx)
    local n = Coerce(value, ctrl.item)
    if n == nil then
        if ctrl.value ~= nil then
            ctx.values[ctrl.valueKey] = ctrl.value
        end
        return
    end
    ctx.values[ctrl.valueKey] = n
    ctrl.value = n
    Paint(ctrl, n)
end

return Progress
