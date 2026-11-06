--[[
  ModMenu widget: progress (a label, a bar and a readout on one line)

  The bar is the engine's own ProgressBar, filled to the value's place in the range min to max.
  It has no input and no onChange, and the value is not saved, because the host drives it with
  ModMenu.SetValue. SetValue moves the bar in place, with no rebuild. The fill colour follows the
  item's button variant, and the readout shows the percent of the range unless the item has a format.

  The theme's progress variant decides the look. stock draws today's tinted bar, which light and dark
  use. bar writes the theme's rounded track and fill into the ProgressBar's own style brushes before
  it is first shown (field note 29). segments draws a row of blocks, each a track shape under a lit
  shape. SetValue shows or hides the lit shapes, because a rounded shape recoloured at run time
  shows a rim (field note 30).
]]

local Theme = require("ModMenu.core.theme")
local Button = require("ModMenu.widgets.button")
local Style = require("ModMenu.core.style")
local Paint = require("ModMenu.core.paint")

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

-- Engine visibility values: a lit block shows without taking clicks, and a hidden one keeps its place.
local VIS_HIDDEN, VIS_HIT_TEST_INVISIBLE = 2, 3
local WHITE = { R = 1, G = 1, B = 1, A = 1 }
-- Far below one segment's share of any range, and far above float error, so 0.3 of 10 lights 3.
local SEGMENT_EPSILON = 1e-9

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

--- The number of segments lit for a value, rounded down: none at min and all n at max.
--- An empty range lights none, so a bad range never divides by zero.
---@param value any
---@param min number
---@param max number
---@param n integer
---@return integer
function Progress.SegmentsLit(value, min, max, n)
    local v = tonumber(value)
    if v == nil or max <= min or n <= 0 then
        return 0
    end
    local f = (v - min) / (max - min)
    if f <= 0 then
        return 0
    end
    if f >= 1 then
        return n
    end
    return math.floor(f * n + SEGMENT_EPSILON)
end

--- The progress style with the item's look merged over it, or nil when no theme is resolved.
--- A look the style module rejects falls back to the theme's own progress style.
local function LookOf(resolved, item)
    if type(resolved) ~= "table" or type(resolved.progress) ~= "table" then
        return nil
    end
    local look = item ~= nil and item.look or nil
    local ok, merged = pcall(Style.ForItem, resolved, "progress", look)
    if ok then
        return merged
    end
    return resolved.progress
end

--- The variant a progress bar draws with. light and dark presets say stock, so they keep today's
--- look, and a missing theme draws stock too.
---@param resolved table|nil
---@param item table|nil
---@return string
function Progress.Variant(resolved, item)
    local pr = LookOf(resolved, item)
    if pr == nil or pr.variant == nil then
        return "stock"
    end
    return pr.variant
end

--- The fill colour of a themed bar. An item that names a button role takes that role's fill, as the
--- stock bar takes the role's button colour, and any other item takes the theme's progress fill.
---@param pr table resolved progress fields
---@param item table
---@param resolved table
---@return table
function Progress.ThemedFill(pr, item, resolved)
    local variant = Button.NormalizeVariant(item.variant) or "default"
    if variant ~= "default" then
        local roles = type(resolved.button) == "table" and resolved.button.roles or nil
        local role = roles ~= nil and roles[variant] or nil
        if role ~= nil and role.fill ~= nil then
            return role.fill
        end
    end
    return pr.fill or WHITE
end

-- The number of cells a segmented bar builds: a whole number of at least one, so a fractional or
-- zero segments value still builds a bar and never divides by zero.
local function SegmentCount(pr)
    local n = math.floor(tonumber(pr.segments) or 12)
    if n < 1 then
        n = 1
    end
    return n
end

--- The lit colour of segment i. A ramp spreads its colours along the bar, or repeats them in turn
--- when cycle is set, as StyleLab's segmented bar does. Without a ramp every segment takes the fill.
--- n is the number of cells built, so the ramp spreads over the cells that exist.
---@param pr table
---@param i integer
---@param fill table
---@param n integer|nil defaults to the count the bar would build
---@return table
function Progress.SegmentColor(pr, i, fill, n)
    local ramp = pr.ramp
    if type(ramp) ~= "table" or #ramp == 0 then
        return fill
    end
    local count = n or SegmentCount(pr)
    local index
    if pr.cycle then
        index = (i - 1) % #ramp + 1
    else
        index = math.min(#ramp, math.floor((i - 1) / count * #ramp) + 1)
    end
    return ramp[index]
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
-- A segmented bar changes only the blocks whose state changed, so a steady value costs no UMG calls.
-- Each block's shown state is recorded only when its call succeeded, so a failed block is retried
-- on the next paint. A block with no recorded state is written whatever its target.
local function ShowSegments(ctrl, value)
    local low, high = RangeOf(ctrl.item)
    local lit = Progress.SegmentsLit(value, low, high, #ctrl.segments)
    local shown = ctrl.cellShown or {}
    ctrl.cellShown = shown
    for i, block in ipairs(ctrl.segments) do
        local on = i <= lit
        if shown[i] ~= on then
            local ok = pcall(function()
                block:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_HIDDEN)
            end)
            if ok then
                shown[i] = on
            end
        end
    end
    ctrl.litCount = lit
end

local function Repaint(ctrl, value)
    if ctrl.segments ~= nil then
        ShowSegments(ctrl, value)
    else
        pcall(function()
            ctrl.bar:SetPercent(Fraction(value, ctrl.item))
        end)
    end
    pcall(function()
        ctrl.readout:SetText(FText(Format(value, ctrl.item)))
    end)
end

-- The themed bar: the engine's ProgressBar with the theme's track and fill written into its own
-- brushes. Its fill colour multiplies over the brush, so it is set to white (field note 29).
local function BuildThemedBar(umg, size, name, pr, fill, fraction)
    local bar = umg.Construct("/Script/UMG.ProgressBar", size, name .. "_Bar")
    pcall(function()
        local st = bar.WidgetStyle
        Paint.Brush(st.BackgroundImage, { fill = pr.track or WHITE, radius = pr.radius })
        Paint.Brush(st.FillImage, { fill = fill, radius = pr.radius })
        Paint.Brush(st.MarqueeImage, { fill = fill, radius = pr.radius })
    end)
    pcall(function()
        bar:SetFillColorAndOpacity(WHITE)
    end)
    pcall(function()
        bar:SetPercent(fraction)
    end)
    return bar
end

-- The segmented bar: n blocks with a gap, each a track shape with a lit shape over it.
-- The lit shapes start hidden, and the first paint shows the lit ones.
local function BuildSegments(umg, size, name, pr, fill)
    local row = umg.Construct("/Script/UMG.HorizontalBox", size, name .. "_Segments")
    local blocks = {}
    local n = SegmentCount(pr)
    local gap = tonumber(pr.gap) or 0
    for i = 1, n do
        local cell = umg.Construct("/Script/UMG.Overlay", row, name .. "_Seg" .. i)
        local trackShape = Paint.Box(cell, name .. "_SegTrack" .. i, { fill = pr.track or WHITE, radius = pr.radius }, 0)
        local lit = Paint.Box(cell, name .. "_SegLit" .. i, { fill = Progress.SegmentColor(pr, i, fill, n),
            radius = pr.radius }, 0)
        pcall(function()
            for _, shape in ipairs({ trackShape, lit }) do
                local slot = cell:AddChildToOverlay(shape)
                slot:SetHorizontalAlignment(0)
                slot:SetVerticalAlignment(0)
            end
        end)
        pcall(function()
            lit:SetVisibility(VIS_HIDDEN)
        end)
        pcall(function()
            local slot = row:AddChildToHorizontalBox(cell)
            slot:SetSize({ SizeRule = 1, Value = 1.0 })
            slot:SetPadding({ Left = i == 1 and 0 or gap, Top = 0, Right = 0, Bottom = 0 })
            slot:SetVerticalAlignment(0)
        end)
        blocks[i] = lit
    end
    return row, blocks
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

    local resolved = ctx.config.resolved
    local variant = Progress.Variant(resolved, item)
    local themed = variant ~= "stock"
    local theme = type(resolved) == "table" and resolved or {}
    local pr = LookOf(resolved, item) or {}
    local body = theme.body or {}
    local data = theme.data or {}

    local root = umg.Construct("/Script/UMG.HorizontalBox", ctx.contentBox, name .. "_Progress")
    local label = umg.Construct("/Script/UMG.TextBlock", root, name .. "_Label")
    if themed then
        umg.StyleText(label, Paint.TextSize(ctx.config, body.size, "fontItem"), nil, body)
        umg.SetLabelText(label, Paint.Caption(item.label, body))
    else
        umg.StyleText(label, ctx.config.fontItem)
        umg.SetLabelText(label, item.label)
    end
    pcall(function()
        local slot = root:AddChildToHorizontalBox(label)
        slot:SetSize({ SizeRule = 1, Value = 1.0 })
        slot:SetVerticalAlignment(2)
    end)

    -- The size box gives the bar a fixed width and height, because a ProgressBar has no desired size of its own.
    local size = umg.Construct("/Script/UMG.SizeBox", root, name .. "_BarSize")
    local bar, segments, barWidget
    if variant == "segments" then
        barWidget, segments = BuildSegments(umg, size, name, pr, Progress.ThemedFill(pr, item, theme))
    elseif themed then
        bar = BuildThemedBar(umg, size, name, pr, Progress.ThemedFill(pr, item, theme), Fraction(current, item))
        barWidget = bar
    else
        bar = umg.Construct("/Script/UMG.ProgressBar", size, name .. "_Bar")
        barWidget = bar
        pcall(function()
            bar:SetFillColorAndOpacity(FillColor(item, colors))
        end)
        pcall(function()
            bar:SetPercent(Fraction(current, item))
        end)
    end
    local barHeight = themed and (tonumber(pr.height) or BAR_HEIGHT) or BAR_HEIGHT
    pcall(function()
        size:SetWidthOverride(BAR_WIDTH)
        size:SetHeightOverride(barHeight)
        size:SetContent(barWidget)
        local slot = root:AddChildToHorizontalBox(size)
        slot:SetSize({ SizeRule = 0, Value = 0.0 })
        slot:SetPadding({ Left = GAP, Top = 0, Right = 0, Bottom = 0 })
        slot:SetVerticalAlignment(2)
    end)

    local readoutSize = umg.Construct("/Script/UMG.SizeBox", root, name .. "_ReadoutSize")
    local readout = umg.Construct("/Script/UMG.TextBlock", readoutSize, name .. "_Readout")
    if themed then
        umg.StyleText(readout, Paint.TextSize(ctx.config, data.size, "fontItem"), nil, data)
    else
        umg.StyleText(readout, ctx.config.fontItem, colors.textMuted)
    end
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
        segments = segments,
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
    if segments ~= nil then
        ShowSegments(ctx.liveControls[#ctx.liveControls], current)
    end
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
    Repaint(ctrl, n)
end

return Progress
