--[[
  ModMenu widget: radio

  One button per option, with the chosen option painted active, stacked or in a row when
  inline = true. Options use the dropdown's shape: plain strings or { label, value } tables.

  Each option is a button control that the button widget paints and polls, so hover, press and
  active chrome match a plain button. The option's onClick only records which option was
  pressed; the radio then stores the value and fires onChange with the poll's ctx.
]]

local Util = require("ModMenu.core.util")
local Options = require("ModMenu.core.options")
local Button = require("ModMenu.widgets.button")

local Radio = {}
Radio.type = "radio"

-- The gap between option buttons. Widget paddings are local to the widget, not spacing tokens.
local OPTION_GAP = 4

local function PlainValue(value)
    if value == nil then
        return nil
    end
    return Util.ToPlainString(value) or tostring(value)
end

--- Return the normalized option whose value equals value, or nil when no option holds it.
local function Resolve(value, item)
    local plain = PlainValue(value)
    if plain == nil or item == nil then
        return nil
    end
    local list = Options.NormalizeOptions(item.options)
    for _, opt in ipairs(list) do
        if opt.value == plain then
            return opt
        end
    end
    return nil
end

Radio._resolve = Resolve

--- The option values joined for error messages, such as "a, b, c".
local function ValueList(item)
    local list = Options.NormalizeOptions(item.options)
    local values = {}
    for i, opt in ipairs(list) do
        values[i] = opt.value
    end
    return table.concat(values, ", ")
end

function Radio.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if type(item.options) ~= "table" then
        error(prefix .. " radio requires an .options array")
    end
    local ok, listOrErr = pcall(Options.NormalizeOptions, item.options)
    if not ok then
        error(prefix .. " " .. tostring(listOrErr))
    end
    -- Unlike a dropdown, a radio has no SetOptions, so an empty group could never offer a choice.
    if #listOrErr == 0 then
        error(prefix .. " radio requires at least one option")
    end
    if item.default ~= nil and Resolve(item.default, item) == nil then
        error(prefix .. " default must be one of " .. ValueList(item))
    end
    if item.inline ~= nil and type(item.inline) ~= "boolean" then
        error(prefix .. " inline must be a boolean")
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

--- Store the default, and replace a value set before Register that no option holds, so the
--- stored value is always an option value or nil.
function Radio.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    local opt = Resolve(values[vkey], item)
    if opt ~= nil then
        values[vkey] = opt.value
        return
    end
    local default = Resolve(item.default, item)
    values[vkey] = default and default.value or nil
end

--- Paint every option button, active for the chosen value and normal for the rest.
local function PaintOptions(ctrl, ctx)
    for _, opt in ipairs(ctrl.optionCtrls) do
        opt.item.active = ctrl.selectedValue ~= nil and opt.value == ctrl.selectedValue
        Button.applyChrome(opt, ctx)
    end
end

local function FocusStubs()
    return {
        enter = function() end,
        leave = function() end,
        activate = function() end,
    }
end

function Radio.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local chosen = Resolve(ctx.values[vkey], item)
    local selectedValue = chosen and chosen.value or nil
    ctx.values[vkey] = selectedValue

    -- The caption and the group share one root, so the radio also fits a horizontal parent.
    local root = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, ctx.namePrefix .. "_Root")
    local caption = umg.Construct("/Script/UMG.TextBlock", root, ctx.namePrefix .. "_Cap")
    umg.StyleText(caption, ctx.config.fontHint)
    umg.SetLabelText(caption, item.label)
    root:AddChildToVerticalBox(caption)

    local inline = item.inline == true
    local groupClass = inline and "/Script/UMG.HorizontalBox" or "/Script/UMG.VerticalBox"
    local group = umg.Construct(groupClass, root, ctx.namePrefix .. "_Group")

    local ctrl = {
        kind = "radio",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        valueKey = vkey,
        selectedValue = selectedValue,
        optionCtrls = {},
        pendingValue = nil,
        focus = FocusStubs(),
    }

    local list = Options.NormalizeOptions(item.options)
    for i, opt in ipairs(list) do
        local fill, button, label = umg.CreateFilledButton(group, ctx.namePrefix .. "_Opt" .. tostring(i), opt.label)
        local slot
        if inline then
            slot = group:AddChildToHorizontalBox(fill)
        else
            slot = group:AddChildToVerticalBox(fill)
        end
        pcall(function()
            if inline then
                slot:SetPadding({ Left = 0, Top = 0, Right = OPTION_GAP, Bottom = 0 })
            else
                slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = OPTION_GAP })
            end
        end)
        local value = opt.value
        local optCtrl = {
            kind = "button",
            value = value,
            widget = button,
            fill = fill,
            labelWidget = label,
            enabled = true,
            wasPressed = false,
            item = {
                variant = "default",
                enabled = true,
                active = false,
                -- The button widget calls onClick synchronously inside its poll, so the radio reads
                -- pendingValue right after and selects with the ctx of that poll.
                onClick = function()
                    ctrl.pendingValue = value
                end,
            },
        }
        table.insert(ctrl.optionCtrls, optCtrl)
    end
    root:AddChildToVerticalBox(group)

    umg.AddToContent(ctx, root)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    PaintOptions(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

--- Store a pressed option, repaint the group and fire onChange when the value changed.
local function TakePending(ctrl, ctx)
    local value = ctrl.pendingValue
    if value == nil then
        return false
    end
    ctrl.pendingValue = nil
    if value == ctrl.selectedValue then
        return true
    end
    ctrl.selectedValue = value
    ctx.values[ctrl.valueKey] = value
    PaintOptions(ctrl, ctx)
    ctx.SafeCall(ctrl.item.onChange, value)
    return true
end

--- Poll every option button for hover, press and its press edge, as a plain button is polled.
function Radio.poll(ctrl, ctx)
    for _, opt in ipairs(ctrl.optionCtrls) do
        Button.poll(opt, ctx)
        if TakePending(ctrl, ctx) then
            return
        end
    end
end

--- LMB latch on the hovered option. Returns true if the click was consumed.
function Radio.pollClick(ctrl, ctx)
    for _, opt in ipairs(ctrl.optionCtrls) do
        if Button.pollClick(opt, ctx) then
            TakePending(ctrl, ctx)
            return true
        end
    end
    return false
end

--- Paint the given value as chosen. A nil value clears the choice. A value that no option holds
--- raises an error naming the allowed values, and the check runs before any painting.
--- Return the option value that value names, or nil for a nil value, and raise for a value no option holds.
--- The registry calls this before it stores a value, so an invalid value raises and the stored value stays as it was.
---@return string|nil
function Radio._check(value, item)
    if value == nil then
        return nil
    end
    local opt = Resolve(value, item)
    if opt == nil then
        error("radio " .. tostring(item.id) .. ": value must be one of " .. ValueList(item))
    end
    return opt.value
end

function Radio.apply(ctrl, value, ctx)
    ctrl.selectedValue = Radio._check(value, ctrl.item)
    PaintOptions(ctrl, ctx)
end

return Radio
