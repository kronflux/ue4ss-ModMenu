--[[
  ModMenu widget: radio

  One button per option, with the chosen option painted active, stacked or in a row when
  inline = true. Options use the dropdown's shape: plain strings or { label, value } tables.

  The theme's choice variant picks the look. stock, as light and dark draw, makes each option a
  button control that the button widget paints and polls, so hover, press and active chrome match
  a plain button. joined, chips, tabs and radio make each option a Paint state button holding a
  mark: a filled segment for joined and chips, an underline for tabs, and a ring with a dot for
  radio. The chosen option's mark is shown and the others hidden, so no shape is recoloured at
  run time (field note 30). Multiselect draws its options with the same functions.

  The option's onClick only records which option was pressed; the radio then stores the value and
  fires onChange with the poll's ctx.
]]

local Util = require("ModMenu.core.util")
local Options = require("ModMenu.core.options")
local Style = require("ModMenu.core.style")
local Paint = require("ModMenu.core.paint")
local Button = require("ModMenu.widgets.button")

local Radio = {}
Radio.type = "radio"

-- The gap between option buttons. Widget paddings are local to the widget, not spacing tokens.
local OPTION_GAP = 4

-- Engine enum values.
local VIS_HIDDEN, VIS_HIT_TEST_INVISIBLE = 2, 3
local H_FILL, H_LEFT, H_CENTER = 0, 1, 2
local V_FILL, V_CENTER = 0, 2

------------------------------------------------------------------------------------------
-- Themed choices, shared with multiselect
------------------------------------------------------------------------------------------

--- The choice variant an item draws. With no resolved theme, as under the spec runner, it is
--- stock; otherwise it is the resolved choice variant with the item's look merged over it.
---@param resolved table|nil
---@param look table|nil
---@return string
function Radio.Variant(resolved, look)
    if resolved == nil then
        return "stock"
    end
    return Style.ForItem(resolved, "choice", look).variant or "stock"
end

--- The caption colour of a themed option. Tabs dim the options that are off; radio keeps the body
--- text, because its ring shows the choice; joined and chips put the mark text on the mark.
---@param cs table the resolved choice style
---@param p table the resolved palette
---@param variant string
---@param on boolean
---@return table
function Radio._choiceTextColor(cs, p, variant, on)
    if variant == "tabs" then
        return on and (cs.tabText or cs.markFill) or p.muted
    end
    if variant == "radio" then
        return p.text
    end
    return on and cs.markText or p.text
end

--- The gap between themed options: chips stand apart, the others nearly touch.
---@param variant string
---@return number
function Radio._choiceGap(variant)
    return variant == "chips" and 6 or 2
end

local function Clear(color)
    return { R = color.R, G = color.G, B = color.B, A = 0 }
end

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local function SetShown(widget, on)
    pcall(function()
        widget:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_HIDDEN)
    end)
end

local function Sized(umg, outer, name, child, width, height)
    local box = umg.Construct("/Script/UMG.SizeBox", outer, name)
    pcall(function()
        if width ~= nil then
            box:SetWidthOverride(width)
        end
        if height ~= nil then
            box:SetHeightOverride(height)
        end
        box:SetContent(child)
    end)
    return box
end

local function OverlayAdd(overlay, widget, pad, halign, valign)
    local slot = overlay:AddChildToOverlay(widget)
    pcall(function()
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
end

--- The themed look a choice item draws with, or nil for stock.
---@param ctx table
---@param item table
---@return table|nil { variant, cs, p, textSpec, size }
function Radio._choiceTheme(ctx, item)
    local resolved = ctx.config and ctx.config.resolved
    if resolved == nil then
        return nil
    end
    local cs = Style.ForItem(resolved, "choice", item.look)
    local variant = cs.variant or "stock"
    if variant == "stock" then
        return nil
    end
    local textSpec = resolved.body
    return {
        variant = variant,
        cs = cs,
        p = resolved.palette,
        textSpec = textSpec,
        size = Paint.TextSize(ctx.config, textSpec and textSpec.size, "fontItem"),
        hintSize = Paint.TextSize(ctx.config, textSpec and textSpec.size, "fontHint"),
    }
end

--- Build the content of one themed option: its caption and the marks shown when it is on or off.
local function OptionContent(umg, outer, name, caption, theme)
    local cs, p, variant = theme.cs, theme.p, theme.variant
    local content = umg.Construct("/Script/UMG.Overlay", outer, name .. "_Content")
    local text = umg.Construct("/Script/UMG.TextBlock", content, name .. "_Text")
    umg.StyleText(text, theme.size, p.text, theme.textSpec)
    umg.SetLabelText(text, Paint.Caption(caption, theme.textSpec))
    pcall(function()
        text:SetJustification(1)
    end)
    local on, off = {}, {}

    if variant == "tabs" then
        local stack = umg.Construct("/Script/UMG.VerticalBox", content, name .. "_Stack")
        local textSlot = stack:AddChildToVerticalBox(text)
        pcall(function()
            textSlot:SetPadding(Paint.Margin({ 0, 4, 0, 4 }))
            textSlot:SetHorizontalAlignment(H_CENTER)
        end)
        local mark, markHost, halign
        if cs.markWidth ~= nil then
            -- A short rounded indicator under the chosen tab.
            mark = Paint.Box(stack, name .. "_Mark", { fill = cs.markFill, radius = 1, pill = true }, 0)
            markHost = Sized(umg, stack, name .. "_MarkSize", mark, cs.markWidth, cs.markHeight or 3)
            halign = H_CENTER
        else
            mark = Paint.Box(stack, name .. "_Mark", { fill = cs.markFill }, 0)
            markHost = Sized(umg, stack, name .. "_MarkSize", mark, nil, 2)
            halign = H_FILL
        end
        local markSlot = stack:AddChildToVerticalBox(markHost)
        pcall(function()
            markSlot:SetHorizontalAlignment(halign)
        end)
        on[#on + 1] = mark
        OverlayAdd(content, stack, 0)
    elseif variant == "radio" then
        -- A ring and the caption beside it. The chosen ring is a separate filled shape with a dot,
        -- so choosing swaps shapes rather than recolouring one.
        local ring = umg.Construct("/Script/UMG.Overlay", content, name .. "_Ring")
        local edge = cs.radioEdge or p.text
        local fillOn = cs.radioFill or cs.markFill
        local ringOff = Paint.Box(ring, name .. "_RingOff", { fill = Clear(edge), outline = edge, width = 1,
            radius = 1, pill = true }, 0)
        local ringOn = Paint.Box(ring, name .. "_RingOn", { fill = fillOn, outline = fillOn, width = 1,
            radius = 1, pill = true }, 0)
        local dot = Paint.Box(ring, name .. "_Dot", { fill = cs.markText or p.text, radius = 1, pill = true }, 0)
        OverlayAdd(ring, ringOff, 0)
        OverlayAdd(ring, ringOn, 0)
        OverlayAdd(ring, Sized(umg, ring, name .. "_DotSize", dot, 6, 6), 0, H_CENTER, V_CENTER)
        on[#on + 1] = ringOn
        on[#on + 1] = dot
        off[#off + 1] = ringOff
        local line = umg.Construct("/Script/UMG.HorizontalBox", content, name .. "_Line")
        local ringSlot = line:AddChildToHorizontalBox(Sized(umg, line, name .. "_RingSize", ring, 14, 14))
        pcall(function()
            ringSlot:SetPadding(Paint.Margin({ 0, 0, 6, 0 }))
            ringSlot:SetVerticalAlignment(V_CENTER)
        end)
        local textSlot = line:AddChildToHorizontalBox(text)
        pcall(function()
            textSlot:SetVerticalAlignment(V_CENTER)
        end)
        OverlayAdd(content, line, { 2, 4, 2, 4 }, H_LEFT, V_CENTER)
    else
        if variant == "chips" then
            -- Every chip keeps its outline; only the mark inside it comes and goes.
            local chip = Paint.Box(content, name .. "_Chip", { fill = Clear(p.text), outline = cs.edge or p.line,
                width = 1, radius = cs.radius, pill = cs.pill }, 0)
            OverlayAdd(content, chip, 0)
        end
        local mark = Paint.Box(content, name .. "_Mark", { fill = cs.markFill, outline = cs.markEdge,
            width = cs.markEdge and 1 or 0, radius = cs.radius, pill = cs.pill }, 0)
        OverlayAdd(content, mark, 0)
        on[#on + 1] = mark
        OverlayAdd(content, text, { 8, 5, 8, 5 }, H_CENTER, V_CENTER)
    end
    return content, text, on, off
end

--- Build one themed option as a Paint state button with a transparent face that washes in on
--- hover and press, as StyleLab's choices do. The caller adds opt.root to its parent.
---@param umg table
---@param outer any
---@param name string
---@param caption string
---@param theme table from Radio._choiceTheme
---@param onClick function
---@return table opt
function Radio._buildOption(umg, outer, name, caption, theme, onClick)
    local cs, p = theme.cs, theme.p
    local content, text, on, off = OptionContent(umg, outer, name, caption, theme)
    local wash = {
        normal = { fill = Alpha(p.text, 0), radius = cs.radius, pill = cs.pill },
        hover = { fill = Alpha(p.text, 0.08), radius = cs.radius, pill = cs.pill },
        pressed = { fill = Alpha(p.text, 0.16), radius = cs.radius, pill = cs.pill },
    }
    local paint = Paint.StateButton(outer, name, wash, content)
    return {
        kind = "button",
        root = paint.root,
        widget = paint.widget,
        paint = paint,
        text = text,
        marksOn = on,
        marksOff = off,
        theme = theme,
        enabled = true,
        wasPressed = false,
        item = { enabled = true, onClick = onClick },
    }
end

--- Show a themed option as on or off: its marks swap visibility and its caption takes the colour
--- of that state.
---@param opt table
---@param on boolean
function Radio._paintOption(opt, on)
    for _, w in ipairs(opt.marksOn) do
        SetShown(w, on)
    end
    for _, w in ipairs(opt.marksOff) do
        SetShown(w, not on)
    end
    local theme = opt.theme
    local color = Radio._choiceTextColor(theme.cs, theme.p, theme.variant, on)
    pcall(function()
        opt.text:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
end

-- A themed option's click, as a plain button's: the press edge is spent, the option records
-- itself, and menu input is reclaimed.
local function FireThemedOption(opt, ctx)
    ctx.Input.SuppressPressEdge(opt)
    opt.item.onClick()
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    -- A second reclaim after 200 ms, as a plain button's click does, catches input the game took
    -- back meanwhile. It touches the PlayerController, so it must run on the game thread.
    ExecuteInGameThreadWithDelay(200, Util.PinFn(function()
        ctx.ReclaimMenuInput()
    end))
end

--- Poll one option for hover, press and its release. A themed option shows its pointer state by
--- shape visibility; a stock option is polled by the button widget.
function Radio._pollOption(opt, ctx)
    if opt.paint == nil then
        Button.poll(opt, ctx)
        return
    end
    Paint.TrackPointer(opt.paint)
    if ctx.Input.ReleaseClick(opt, opt.widget) then
        FireThemedOption(opt, ctx)
    end
end

--- The mouse-down latch on one option. Returns true if the click was consumed.
function Radio._pollOptionClick(opt, ctx)
    if opt.paint == nil then
        return Button.pollClick(opt, ctx)
    end
    local consumed, fireNow = ctx.Input.ArmClick(opt, opt.widget)
    if fireNow then
        FireThemedOption(opt, ctx)
        return true
    end
    return consumed
end

--- Wrap a group of joined options in their track: a filled frame a little rounder than the
--- options, so the chosen segment sits inside it. Other variants return the group unchanged.
---@param umg table
---@param outer any
---@param name string
---@param group any
---@param theme table
---@return any
function Radio._choiceFrame(umg, outer, name, group, theme)
    if theme.variant ~= "joined" then
        return group
    end
    local cs, p = theme.cs, theme.p
    local radius = cs.radius
    if type(radius) == "number" and radius > 0 and not cs.pill then
        radius = radius + 3
    end
    local frame = Paint.Box(outer, name, {
        fill = cs.trackFill or p.surface,
        outline = cs.edge,
        width = cs.edge and 1 or 0,
        radius = radius,
        pill = cs.pill,
    }, 3)
    pcall(function()
        local slot = frame:SetContent(group)
        if slot ~= nil then
            slot:SetHorizontalAlignment(H_FILL)
            slot:SetVerticalAlignment(V_FILL)
        end
    end)
    return frame
end

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
        local on = ctrl.selectedValue ~= nil and opt.value == ctrl.selectedValue
        opt.item.active = on
        if opt.paint ~= nil then
            Radio._paintOption(opt, on)
        else
            Button.applyChrome(opt, ctx)
        end
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
    local theme = Radio._choiceTheme(ctx, item)
    local root = umg.Construct("/Script/UMG.VerticalBox", ctx.contentBox, ctx.namePrefix .. "_Root")
    local caption = umg.Construct("/Script/UMG.TextBlock", root, ctx.namePrefix .. "_Cap")
    if theme ~= nil then
        umg.StyleText(caption, theme.hintSize, nil, theme.textSpec)
        umg.SetLabelText(caption, Paint.Caption(item.label, theme.textSpec))
    else
        umg.StyleText(caption, ctx.config.fontHint)
        umg.SetLabelText(caption, item.label)
    end
    root:AddChildToVerticalBox(caption)

    local inline = item.inline == true
    local groupClass = inline and "/Script/UMG.HorizontalBox" or "/Script/UMG.VerticalBox"
    local group = umg.Construct(groupClass, root, ctx.namePrefix .. "_Group")
    local gap = theme ~= nil and Radio._choiceGap(theme.variant) or OPTION_GAP

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
        local value = opt.value
        local name = ctx.namePrefix .. "_Opt" .. tostring(i)
        local themedOpt, fill, button, label = nil, nil, nil, nil
        if theme ~= nil then
            themedOpt = Radio._buildOption(umg, group, name, opt.label, theme, function()
                ctrl.pendingValue = value
            end)
            themedOpt.value = value
            fill = themedOpt.root
        else
            fill, button, label = umg.CreateFilledButton(group, name, opt.label)
        end
        local slot
        if inline then
            slot = group:AddChildToHorizontalBox(fill)
        else
            slot = group:AddChildToVerticalBox(fill)
        end
        pcall(function()
            if inline then
                slot:SetPadding({ Left = 0, Top = 0, Right = gap, Bottom = 0 })
                -- Themed options share a row evenly, as a segmented control does.
                if theme ~= nil then
                    slot:SetSize({ SizeRule = 1, Value = 1.0 })
                    slot:SetVerticalAlignment(V_FILL)
                end
            else
                slot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = gap })
            end
        end)
        local optCtrl = themedOpt or {
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
    if theme ~= nil then
        root:AddChildToVerticalBox(Radio._choiceFrame(umg, root, ctx.namePrefix .. "_Track", group, theme))
    else
        root:AddChildToVerticalBox(group)
    end

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
        Radio._pollOption(opt, ctx)
        if TakePending(ctrl, ctx) then
            return
        end
    end
end

--- LMB latch on the hovered option. Returns true if the click was consumed.
function Radio.pollClick(ctrl, ctx)
    for _, opt in ipairs(ctrl.optionCtrls) do
        if Radio._pollOptionClick(opt, ctx) then
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
