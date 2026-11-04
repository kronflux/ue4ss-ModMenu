--[[
  ModMenu widget: checkbox

  Desktop: native UCheckBox, poll IsChecked().
  pointerMode = "touch": UButton toggle (same onChange(bool)). Native UCheckBox
  on a handheld needs a cursor + A; constructed buttons fire press-edge from a tap.
]]

local Button = require("ModMenu.widgets.button")

local Checkbox = {}
Checkbox.type = "checkbox"

local function Caption(item, isOn)
    if item.showState == false then
        return item.label
    end
    return string.format("%s: %s", item.label, isOn and "ON" or "OFF")
end

Checkbox.Caption = Caption

local function UseTouchButton(ctx)
    return ctx ~= nil and ctx.Input ~= nil and ctx.Input.IsTouch and ctx.Input.IsTouch()
end

local function PaintToggle(ctrl, ctx, isOn)
    ctrl.paintItem = {
        active = isOn == true,
        enabled = true,
        variant = "default",
    }
    -- The paint table is kept, because it holds the fill colours the pointer poll repaints from.
    ctrl.paint = ctrl.paint or {
        kind = "checkbox",
        widget = ctrl.widget,
        fill = ctrl.fill,
        labelWidget = ctrl.label or ctrl.labelWidget,
    }
    ctrl.paint.item = ctrl.paintItem
    Button.applyChrome(ctrl.paint, ctx)
end

function Checkbox.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

function Checkbox.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if values[vkey] == nil then
        values[vkey] = item.default and true or false
    end
end

function Checkbox.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local current = ctx.values[vkey]
    if current == nil then
        current = item.default and true or false
        ctx.values[vkey] = current
    end

    local asButton = UseTouchButton(ctx)
    local widget
    local label
    local fill
    if asButton then
        fill, widget, label = umg.CreateFilledButton(ctx.contentBox, ctx.namePrefix, Caption(item, current))
    else
        widget, label = umg.CreateLabeledToggle(
            ctx.contentBox,
            ctx.namePrefix,
            Caption(item, current),
            current
        )
    end
    umg.AddToContent(ctx, fill or widget)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    local ctrl = {
        kind = "checkbox",
        sectionId = ctx.section.id,
        item = item,
        widget = widget,
        fill = fill,
        label = label,
        labelWidget = label,
        valueKey = vkey,
        asButton = asButton,
        wasPressed = false,
    }
    if asButton then
        PaintToggle(ctrl, ctx, current)
    end
    table.insert(ctx.liveControls, ctrl)
end

local function FireToggle(ctrl, ctx, path)
    local nextOn = not (ctx.values[ctrl.valueKey] == true)
    ctx.values[ctrl.valueKey] = nextOn
    ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, nextOn))
    PaintToggle(ctrl, ctx, nextOn)
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    ctx.SafeCall(ctrl.item.onChange, nextOn)
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    return true
end

--- Native box: IsChecked. Touch button: IsPressed rising edge.
function Checkbox.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    if ctrl.asButton then
        ctx.umg.TrackPointer(ctrl.paint)
        if ctx.Input.ReleaseClick(ctrl, ctrl.widget) then
            FireToggle(ctrl, ctx, "release")
        end
        return
    end
    local ok, checked = pcall(function()
        return ctrl.widget:IsChecked()
    end)
    if ok and checked ~= ctx.values[ctrl.valueKey] then
        ctx.values[ctrl.valueKey] = checked
        ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, checked))
        ctx.SafeCall(ctrl.item.onChange, checked)
        ctx.ReclaimMenuInput()
    end
end

function Checkbox.pollClick(ctrl, ctx)
    if not ctrl.asButton then
        return false
    end
    local consumed, fireNow = ctx.Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        return FireToggle(ctrl, ctx, "latch-hover")
    end
    return consumed
end

function Checkbox.apply(ctrl, value, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    local on = value and true or false
    if ctrl.asButton then
        ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, on))
        PaintToggle(ctrl, ctx, on)
        return
    end
    pcall(function()
        ctrl.widget:SetIsChecked(on)
    end)
    ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, on))
end

return Checkbox
