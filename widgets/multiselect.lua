--[[
  ModMenu widget: multiselect

  A caption and one toggle button per option, laid out in 1 to 4 columns. Each button shows its
  label with a check mark and is painted active while its option is on. The value is an array of
  the checked option values, in option order. Options use the dropdown's shape: plain strings or
  { label, value } tables.

  Each option is a button control that the button widget paints and polls, as the radio does.
  The option's onClick only records which option was pressed; the multiselect then toggles it,
  stores the array and fires onChange with a copy of the array.

  The group's height depends on the option count, so a row cannot hold a multiselect. A fold can.
]]

local Options = require("ModMenu.core.options")
local Button = require("ModMenu.widgets.button")

local Multiselect = {}
Multiselect.type = "multiselect"

local MIN_COLUMNS = 1
local MAX_COLUMNS = 4

-- The gap around each option button, local to this widget as the other widget paddings are.
local OPTION_GAP = 2

-- EHorizontalAlignment and EVerticalAlignment both use 0 for Fill.
local ALIGN_FILL = 0

--- The option values joined for error messages, such as "a, b, c".
local function ValueList(item)
    local list = Options.NormalizeOptions(item.options)
    local values = {}
    for i, opt in ipairs(list) do
        values[i] = opt.value
    end
    return table.concat(values, ", ")
end

--- The set of option values of an item, for a membership test.
local function OptionSet(item)
    local known = {}
    for _, opt in ipairs((Options.NormalizeOptions(item.options))) do
        known[opt.value] = true
    end
    return known
end

--- Return the values that are options, in option order and without duplicates.
--- A value that is not a table gives an empty array, and a copy is always returned.
---@param values any
---@param item table
---@return string[]
function Multiselect._normalize(values, item)
    local result = {}
    if type(values) ~= "table" then
        return result
    end
    local wanted = {}
    for _, entry in ipairs(values) do
        if type(entry) == "string" then
            wanted[entry] = true
        end
    end
    for _, opt in ipairs((Options.NormalizeOptions(item.options))) do
        if wanted[opt.value] then
            wanted[opt.value] = nil
            result[#result + 1] = opt.value
        end
    end
    return result
end

--- Return the array with value switched on when it was off and off when it was on.
--- The input is not changed. A value that is not an option leaves the array as it was.
---@param values any
---@param value string
---@param item table
---@return string[]
function Multiselect._toggle(values, value, item)
    local current = Multiselect._normalize(values, item)
    if not OptionSet(item)[value] then
        return current
    end
    local want = {}
    local found = false
    for _, entry in ipairs(current) do
        if entry == value then
            found = true
        else
            want[#want + 1] = entry
        end
    end
    if not found then
        want[#want + 1] = value
    end
    return Multiselect._normalize(want, item)
end

--- The text on an option button: its label behind a mark that says whether it is on.
--- The mark is plain ASCII, because the game's font may lack a check glyph.
---@param label string
---@param checked boolean
---@return string
function Multiselect._caption(label, checked)
    return (checked and "[x] " or "[ ] ") .. tostring(label)
end

function Multiselect.validate(item, sectionId, index)
    local prefix = string.format("Register(%s) items[%d]", tostring(sectionId), index)
    if item.id == nil or item.id == "" then
        error(prefix .. " requires .id")
    end
    if item.label == nil then
        error(prefix .. " requires .label")
    end
    if type(item.options) ~= "table" then
        error(prefix .. " multiselect requires an .options array")
    end
    local ok, listOrErr = pcall(Options.NormalizeOptions, item.options)
    if not ok then
        error(prefix .. " " .. tostring(listOrErr))
    end
    if #listOrErr == 0 then
        error(prefix .. " multiselect requires at least one option")
    end
    if item.default ~= nil then
        if type(item.default) ~= "table" then
            error(prefix .. " default must be an array")
        end
        local known = OptionSet(item)
        for _, entry in ipairs(item.default) do
            if type(entry) ~= "string" or not known[entry] then
                error(prefix .. " default must be one of " .. ValueList(item))
            end
        end
    end
    if item.columns ~= nil then
        local c = item.columns
        if type(c) ~= "number" or c ~= math.floor(c) or c < MIN_COLUMNS or c > MAX_COLUMNS then
            error(prefix .. " columns must be a number from 1 to 4")
        end
    end
    if item.onChange ~= nil and type(item.onChange) ~= "function" then
        error(prefix .. " onChange must be a function")
    end
end

--- Store the default, and replace a value set before Register with its normalized form, so the
--- stored value is always an array of option values in option order.
function Multiselect.seed(sectionId, item, values)
    if not item.id then
        return
    end
    local vkey = tostring(sectionId) .. "." .. tostring(item.id)
    if type(values[vkey]) == "table" then
        values[vkey] = Multiselect._normalize(values[vkey], item)
    else
        values[vkey] = Multiselect._normalize(item.default, item)
    end
end

--- Paint every option button: active and marked for a checked value, normal and unmarked for the rest.
local function PaintOptions(ctrl, ctx)
    local on = {}
    for _, value in ipairs(ctrl.selected) do
        on[value] = true
    end
    for _, opt in ipairs(ctrl.optionCtrls) do
        local checked = on[opt.value] == true
        opt.item.active = checked
        pcall(function()
            if opt.labelWidget ~= nil and ctx.umg ~= nil then
                ctx.umg.SetLabelText(opt.labelWidget, Multiselect._caption(opt.label, checked))
            end
        end)
        Button.applyChrome(opt, ctx)
    end
end

--- The item table of one option button. Its onClick records the press for TakePending to read.
function Multiselect._optionItem(ctrl, value)
    return {
        variant = "default",
        enabled = true,
        active = false,
        -- The button widget calls onClick synchronously inside its poll, so the multiselect reads
        -- pendingValue right after and toggles with the ctx of that poll.
        onClick = function()
            ctrl.pendingValue = value
        end,
    }
end

function Multiselect.build(ctx)
    local umg = ctx.umg
    local item = ctx.item
    local vkey = ctx.ValueKey(ctx.section.id, item.id)
    local selected = Multiselect._normalize(ctx.values[vkey], item)
    ctx.values[vkey] = selected

    local root = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, ctx.namePrefix .. "_Root")
    local caption = umg.Construct("/Script/UMG.TextBlock", root, ctx.namePrefix .. "_Cap")
    umg.StyleText(caption, ctx.config.fontHint)
    umg.SetLabelText(caption, item.label)
    root:AddChildToVerticalBox(caption)

    local columns = item.columns or MIN_COLUMNS
    local grid = umg.Construct("/Script/UMG.UniformGridPanel", root, ctx.namePrefix .. "_Grid")
    pcall(function()
        grid:SetSlotPadding({ Left = OPTION_GAP, Top = OPTION_GAP, Right = OPTION_GAP, Bottom = OPTION_GAP })
    end)

    local ctrl = {
        kind = "multiselect",
        sectionId = ctx.section.id,
        item = item,
        widget = root,
        valueKey = vkey,
        selected = selected,
        optionCtrls = {},
        pendingValue = nil,
        focus = {
            enter = function() end,
            leave = function() end,
            activate = function() end,
        },
    }

    local list = Options.NormalizeOptions(item.options)
    for i, opt in ipairs(list) do
        local fill, button, label = umg.CreateFilledButton(grid, ctx.namePrefix .. "_Opt" .. tostring(i), opt.label)
        local row = math.floor((i - 1) / columns)
        local col = (i - 1) % columns
        pcall(function()
            local slot = grid:AddChildToUniformGrid(fill, row, col)
            slot:SetHorizontalAlignment(ALIGN_FILL)
            slot:SetVerticalAlignment(ALIGN_FILL)
        end)
        table.insert(ctrl.optionCtrls, {
            kind = "button",
            value = opt.value,
            label = opt.label,
            widget = button,
            fill = fill,
            labelWidget = label,
            enabled = true,
            wasPressed = false,
            item = Multiselect._optionItem(ctrl, opt.value),
        })
    end
    root:AddChildToVerticalBox(grid)

    umg.AddToContent(ctx, root)
    umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
    PaintOptions(ctrl, ctx)
    table.insert(ctx.liveControls, ctrl)
end

--- Toggle a pressed option, store the array, repaint and fire onChange.
local function TakePending(ctrl, ctx)
    local value = ctrl.pendingValue
    if value == nil then
        return false
    end
    ctrl.pendingValue = nil
    ctrl.selected = Multiselect._toggle(ctrl.selected, value, ctrl.item)
    ctx.values[ctrl.valueKey] = ctrl.selected
    PaintOptions(ctrl, ctx)
    ctx.SafeCall(ctrl.item.onChange, Multiselect._normalize(ctrl.selected, ctrl.item))
    return true
end

--- Poll every option button for hover, press and its release, as a plain button is polled.
function Multiselect.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    for _, opt in ipairs(ctrl.optionCtrls) do
        Button.poll(opt, ctx)
        if TakePending(ctrl, ctx) then
            return
        end
    end
end

--- The mouse-down latch on an option is claimed here and fired on release by poll.
--- Returns true if the click was consumed.
function Multiselect.pollClick(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return false
    end
    for _, opt in ipairs(ctrl.optionCtrls) do
        if Button.pollClick(opt, ctx) then
            TakePending(ctrl, ctx)
            return true
        end
    end
    return false
end

--- Set the value from the host. The array is normalized and stored, and onChange does not fire,
--- because the host supplied the value.
function Multiselect.apply(ctrl, value, ctx)
    ctrl.selected = Multiselect._normalize(value, ctrl.item)
    ctx.values[ctrl.valueKey] = ctrl.selected
    PaintOptions(ctrl, ctx)
end

return Multiselect
