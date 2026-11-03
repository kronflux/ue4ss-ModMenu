--[[
  ModMenu widget: number (labeled EditableTextBox, parsed/clamped numeric value)
]]

local Options = require("ModMenu.core.options")
local Util = require("ModMenu.core.util")

local Number = {}
Number.type = "number"

local function Prefix(sectionId, index)
    return string.format("Register(%s) items[%d]", tostring(sectionId), index)
end

-- This rounds half away from zero, and every integer path in this widget uses it as the one rule.
-- A negative value uses ceil, because floor(n - 0.5) would turn -2.7 and even -3 into -4.
local function RoundInteger(n)
    if n >= 0 then
        return math.floor(n + 0.5)
    end
    return math.ceil(n - 0.5)
end

-- This rounds an integer item's value and clamps it to the item's range.
-- Text and number arguments share this so "2.7" and 2.7 land on the same value.
local function RoundAndClamp(n, item)
    if item.integer then
        n = RoundInteger(n)
    end
    if item.min ~= nil and n < item.min then
        n = item.min
    end
    if item.max ~= nil and n > item.max then
        n = item.max
    end
    return n
end

local function CoerceDefault(item)
    local n = tonumber(item.default)
    if n == nil then
        n = 0
    end
    return RoundAndClamp(n, item)
end

local function FormatValue(n, integer)
    if integer then
        return tostring(RoundInteger(n))
    end
    -- Trim trailing zeros from floats for cleaner fields.
    local s = string.format("%.6f", n)
    s = s:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    return s
end

local function ParseText(text, item)
    if text == nil then
        return nil
    end
    local trimmed = tostring(text):match("^%s*(.-)%s*$")
    if trimmed == nil or trimmed == "" or trimmed == "-" or trimmed == "." or trimmed == "-." then
        return nil
    end
    local n = tonumber(trimmed)
    if n == nil then
        return nil
    end
    if item.integer then
        n = RoundInteger(n)
    end
    -- Below min: treat as incomplete so typing "10" with min=10 is not forced to 10 on "1".
    if item.min ~= nil and n < item.min then
        return nil
    end
    if item.max ~= nil and n > item.max then
        n = item.max
    end
    return n
end

-- This turns a value from Set into a number in the item's range, or nil when it is not numeric.
-- Set passes whatever the caller gave, so a typed "5" must become 5 before it reaches the store.
-- A nil value resets the item, so it returns the item's default after the same rounding and clamping.
local function coerce(raw, item)
    if raw == nil then
        return CoerceDefault(item)
    end
    if raw == "" then
        return nil
    end
    local n = tonumber(raw)
    if n == nil then
        return nil
    end
    return RoundAndClamp(n, item)
end

-- The spec runs without the game and cannot build a widget, so the module exposes these helpers.
Number._coerce = coerce
Number._parseText = ParseText
Number._formatValue = FormatValue

function Number.validate(item, sectionId, index)
    local prefix = Prefix(sectionId, index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
    if item.min ~= nil and type(item.min) ~= "number" then
        error(prefix .. " min must be a number")
    end
    if item.max ~= nil and type(item.max) ~= "number" then
        error(prefix .. " max must be a number")
    end
    if item.min ~= nil and item.max ~= nil and item.min > item.max then
        error(prefix .. " min must be <= max")
    end
    if item.default ~= nil and tonumber(item.default) == nil then
        error(prefix .. " default must be numeric")
    end
    if item.fieldWidth ~= nil and (type(item.fieldWidth) ~= "number" or item.fieldWidth < 1) then
        error(prefix .. " fieldWidth must be a positive number")
    end
    if item.labelWidth ~= nil and (type(item.labelWidth) ~= "number" or item.labelWidth < 1) then
        error(prefix .. " labelWidth must be a positive number")
    end
    Util.ValidateDebounceMs(item, prefix)
end

function Number.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    -- A Set before Register stores the caller's value as given, because no item is known yet.
    -- Register seeds every item, so the stored value is coerced here the same way Set coerces it after Register.
    -- A missing value and a value that is not numeric both become the item's default.
    local n = coerce(values[vkey], item)
    if n == nil then
        n = CoerceDefault(item)
    end
    values[vkey] = n
end

function Number.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil or tonumber(current) == nil then
        current = CoerceDefault(item)
        ctx.values[vkey] = current
    end

    local fillField = ctx.layout ~= "horizontal" and item.fill ~= false
    local root, edit, label = umg.CreateLabeledEditable(
        ctx.contentBox,
        ctx.namePrefix,
        item.label,
        FormatValue(current, item.integer == true),
        {
            fontSize = ctx.config.fontItem,
            fieldWidth = item.fieldWidth or (ctx.layout == "horizontal" and 72 or 96),
            labelWidth = item.labelWidth,
            hint = item.placeholder,
            fillField = fillField,
        }
    )
    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and item.fill == true,
    })
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)

    table.insert(ctx.liveControls, {
        kind = "number",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        edit = edit,
        label = label,
        valueKey = vkey,
        lastText = FormatValue(current, item.integer == true),
        lastFiredOnChange = current,
        debounceMs = Util.ResolveDebounceMs(item, Util.DEFAULT_INPUT_DEBOUNCE_MS),
    })
end

--- Poll typed text; update store when a valid number is parsed.
--- Get/store update immediately; onChange is debounced (default 250ms).
--- Do not reclaim input here — that steals focus from the EditableTextBox.
function Number.poll(ctrl, ctx)
    if ctrl.edit == nil then
        return
    end
    local text = Options.GetWidgetPlainText(ctrl.edit)
    if text ~= ctrl.lastText then
        ctrl.lastText = text
        local n = ParseText(text, ctrl.item)
        if n ~= nil and n ~= ctx.values[ctrl.valueKey] then
            ctx.values[ctrl.valueKey] = n
            Util.ScheduleDebouncedOnChange(ctrl, ctrl.debounceMs)
        end
    end
    Util.FlushDebouncedOnChange(ctrl, ctx)
end

function Number.apply(ctrl, value, ctx)
    if ctrl.edit == nil then
        return
    end
    local n
    if type(value) ~= "number" then
        -- A non-number is coerced, so a direct apply with text still stores a number.
        n = coerce(value, ctrl.item)
        if n == nil then
            return
        end
    else
        n = RoundAndClamp(value, ctrl.item)
    end
    local text = FormatValue(n, ctrl.item.integer == true)
    pcall(function()
        ctrl.edit:SetText(FText(text))
    end)
    ctrl.lastText = text
    ctx.values[ctrl.valueKey] = n
    Util.ClearDebouncedOnChange(ctrl, n)
end

return Number
