--[[
  ModMenu widget: stepper (a label, a minus button, a readout and a plus button on one line)

  One click moves the value one step and clamps it to min and max. Holding a button repeats: the
  first repeat comes 400 ms after the press and then one every 100 ms while it stays held.
  A click fires on release and a touch tap on press, as every button-like control does, and a
  release that ends a run of repeats adds no step of its own.
]]

local Theme = require("ModMenu.core.theme")

local Stepper = {}
Stepper.type = "stepper"

local REPEAT_DELAY_MS = 400
local REPEAT_INTERVAL_MS = 100
-- These are the widget's own dimensions, not shell spacing tokens, like the number field's width.
local READOUT_WIDTH = 64
local BUTTON_GAP = 6
local ITEM_PAD = 8

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

-- This keeps a float computation from leaving values such as 0.30000000000000004 in the store.
local function Tidy(n)
    return tonumber(string.format("%.12g", n)) or n
end

local function Clamp(n, item)
    if item.min ~= nil and n < item.min then
        return item.min
    end
    if item.max ~= nil and n > item.max then
        return item.max
    end
    return n
end

-- This snaps a number to the item's step counted from min (or from zero without a min), rounds an
-- integer item and clamps. The ends of the range stay as they are, so max stays reachable when the
-- range is not a whole number of steps.
local function Snap(n, item)
    n = Clamp(n, item)
    local step = item.step or 1
    local origin = item.min or 0
    if n ~= item.min and n ~= item.max then
        n = Tidy(origin + RoundInteger((n - origin) / step) * step)
    end
    if item.integer then
        n = RoundInteger(n)
    end
    return Clamp(n, item)
end

local function CoerceDefault(item)
    local n = tonumber(item.default)
    if n == nil then
        n = item.min or 0
    end
    return Snap(n, item)
end

-- This turns a value from Set, seed or a step into a snapped number in range, or nil when it is not numeric.
-- A nil value resets the item to its default, as Set(nil) does on the number and slider items.
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

-- This returns the value one step from `value`. A value off the step grid, such as an uneven max,
-- moves to the nearest grid point in the direction asked, so stepping down from max never skips one.
local function Next(value, dir, item)
    local n = tonumber(value) or CoerceDefault(item)
    local step = item.step or 1
    local origin = item.min or 0
    local index = (n - origin) / step
    local eps = 1e-9
    if dir > 0 then
        index = math.floor(index + eps) + 1
    else
        index = math.ceil(index - eps) - 1
    end
    return Snap(origin + index * step, item)
end

-- A format string goes through string.format. Without one, an integer item prints as a whole number
-- and any other value uses %g. A format that fails falls back to the default, so a bad string never blanks the readout.
local function Format(value, item)
    if type(item.format) == "string" then
        local ok, text = pcall(string.format, item.format, value)
        if ok then
            return text
        end
    end
    if item.integer then
        return string.format("%d", RoundInteger(value))
    end
    return string.format("%g", value)
end

-- This says whether a held button is due another step. heldMs is how long it has been down and
-- lastMs the held time at the previous step, with 0 for none yet.
local function Repeat(heldMs, lastMs)
    if lastMs == nil or lastMs <= 0 then
        return heldMs >= REPEAT_DELAY_MS
    end
    return heldMs - lastMs >= REPEAT_INTERVAL_MS
end

-- The spec runs without the game and cannot build a widget, so the module exposes these helpers.
Stepper._coerce = Coerce
Stepper._next = Next
Stepper._format = Format
Stepper._repeat = Repeat
-- The clock in seconds. It is a module field so that a spec can replace it with a fake clock.
Stepper._clock = os.clock

function Stepper.validate(item, sectionId, index)
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
    if item.min ~= nil and item.max ~= nil and item.min >= item.max then
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
    if item.format ~= nil and type(item.format) ~= "string" then
        error(prefix .. " format must be a string")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

function Stepper.seed(sectionId, item, values)
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

local function Paint(ctrl, value)
    pcall(function()
        ctrl.readout:SetText(FText(Format(value, ctrl.item)))
    end)
end

function Stepper.build(ctx)
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

    local root = umg.Construct("/Script/UMG.HorizontalBox", ctx.contentBox, name .. "_Stepper")
    local label = umg.Construct("/Script/UMG.TextBlock", root, name .. "_Label")
    umg.StyleText(label, ctx.config.fontItem)
    umg.SetLabelText(label, item.label)
    pcall(function()
        local slot = root:AddChildToHorizontalBox(label)
        slot:SetSize({ SizeRule = 1, Value = 1.0 })
        slot:SetVerticalAlignment(2)
    end)

    local buttons = {}
    local readout
    local function AddButton(key, text, dir)
        local fill, button, caption = umg.CreateFilledButton(root, name .. "_" .. key, text, nil, ctx.config.fontItem)
        pcall(function()
            local slot = root:AddChildToHorizontalBox(fill)
            slot:SetSize({ SizeRule = 0, Value = 0.0 })
            slot:SetPadding({ Left = BUTTON_GAP, Top = 0, Right = 0, Bottom = 0 })
            slot:SetVerticalAlignment(2)
        end)
        local button_ctrl = { widget = button, fill = fill, labelWidget = caption, dir = dir }
        umg.SetFill(button_ctrl, colors.buttonBg)
        table.insert(buttons, button_ctrl)
    end
    AddButton("minus", "-", -1)
    local size = umg.Construct("/Script/UMG.SizeBox", root, name .. "_ReadoutSize")
    readout = umg.Construct("/Script/UMG.TextBlock", size, name .. "_Readout")
    umg.StyleText(readout, ctx.config.fontItem, colors.textMuted)
    umg.SetLabelText(readout, Format(current, item))
    pcall(function()
        size:SetWidthOverride(READOUT_WIDTH)
        size:SetContent(readout)
        readout:SetJustification(1)
        local slot = root:AddChildToHorizontalBox(size)
        slot:SetSize({ SizeRule = 0, Value = 0.0 })
        slot:SetPadding({ Left = BUTTON_GAP, Top = 0, Right = 0, Bottom = 0 })
        slot:SetVerticalAlignment(2)
    end)
    AddButton("plus", "+", 1)

    umg.AddToContent(ctx, root, {
        fill = ctx.layout == "horizontal" and item.fill == true,
    })
    umg.AddItemPad(ctx, name .. "_Pad", ITEM_PAD)

    table.insert(ctx.liveControls, {
        kind = "stepper",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        readout = readout,
        valueKey = vkey,
        value = current,
        buttons = buttons,
        -- The stepper takes no part in focus navigation yet. These stubs keep the control's shape uniform.
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    })
end

-- This moves the value one step, stores it and fires onChange when it changed. A click at either
-- end changes nothing and so fires nothing. A repeat step leaves the menu input alone, because
-- reclaiming it resets the engine's input mode and cancels the held press, so the
-- reclaim waits until the hold ends (see PollButton).
local function FireStep(ctrl, ctx, button, repeating)
    local current = tonumber(ctx.values[ctrl.valueKey]) or CoerceDefault(ctrl.item)
    local n = Next(current, button.dir, ctrl.item)
    ctx.Input.SuppressPressEdge(button)
    if n ~= current then
        Stepper.apply(ctrl, n, ctx)
        ctx.SafeCall(ctrl.item.onChange, n)
    end
    if not repeating then
        ctx.Input.IgnoreClicks(2)
        ctx.ReclaimMenuInput()
    end
end

-- This watches one button: it repeats while the button is held and fires the click on release.
-- A release that ends a run of repeats is dropped, because the repeats already moved the value.
local function PollButton(ctrl, ctx, button)
    ctx.umg.TrackPointer(button)
    local down = ctx.Input.WidgetIsDown(button.widget)
    if down then
        local now = Stepper._clock() * 1000
        if button.downAt == nil then
            button.downAt = now
            button.lastStepMs = 0
        end
        local held = now - button.downAt
        if Repeat(held, button.lastStepMs) then
            button.lastStepMs = held
            button.repeated = true
            FireStep(ctrl, ctx, button, true)
        end
    else
        button.downAt = nil
    end
    local fire = ctx.Input.ReleaseClick(button, button.widget)
    if fire and not button.repeated then
        FireStep(ctrl, ctx, button)
    end
    if not down then
        if button.repeated then
            -- The run of repeats is over, so the input the repeats left alone is reclaimed once.
            ctx.Input.IgnoreClicks(2)
            ctx.ReclaimMenuInput()
        end
        button.repeated = false
    end
end

--- ItemState calls this when the stepper's state changes. The shell stops polling a disabled
--- stepper, so a hold in progress is dropped here: it would otherwise repeat or click once the
--- stepper is enabled again, and the input a run of repeats left alone is reclaimed now.
function Stepper.onItemState(ctrl, enabled, _visible, ctx)
    if enabled then
        return
    end
    for _, button in ipairs(ctrl.buttons or {}) do
        if button.repeated and ctx.ReclaimMenuInput then
            ctx.ReclaimMenuInput()
        end
        button.downAt = nil
        button.repeated = false
        ctx.Input.ClearPress(button)
    end
end

function Stepper.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    for _, button in ipairs(ctrl.buttons or {}) do
        PollButton(ctrl, ctx, button)
    end
end

--- The mouse-down latch on a button is claimed here and fired on release by poll.
--- @return boolean true if click consumed
function Stepper.pollClick(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return false
    end
    for _, button in ipairs(ctrl.buttons or {}) do
        local consumed, fireNow = ctx.Input.ArmClick(button, button.widget)
        if consumed then
            if fireNow then
                FireStep(ctrl, ctx, button)
            end
            return true
        end
    end
    return false
end

--- Set the value from the host. The value is coerced and stored, and onChange does not fire,
--- because the host supplied the value. The registry stores Set's raw value before it calls apply,
--- so a value that is not numeric puts the last good value back in the store.
function Stepper.apply(ctrl, value, ctx)
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

return Stepper
