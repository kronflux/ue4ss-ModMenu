--[[
  ModMenu widget: checkbox

  The theme's toggle variant picks the look (Checkbox.Variant).
  stock, desktop: native UCheckBox, poll IsChecked().
  stock, pointerMode = "touch": UButton toggle (same onChange(bool)). Native UCheckBox
  on a handheld needs a cursor + A; constructed buttons fire press-edge from a tap.
  switch, square, check, text: a transparent Button over a row holding the label and the
  control's shapes. Each on and off look is its own shape, swapped by visibility, because a
  rounded shape recoloured with SetBrushColor shows a rim (field note 30).
]]

local Button = require("ModMenu.widgets.button")

local Checkbox = {}
Checkbox.type = "checkbox"

local VARIANTS = { stock = true, switch = true, square = true, check = true, text = true }

-- Engine enum values.
local VIS_HIDDEN, VIS_HIT_TEST_INVISIBLE = 2, 3
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3
local V_FILL, V_TOP, V_CENTER = 0, 1, 2

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

--- The toggle look a theme draws. light and dark name the stock variant in their presets, so their
--- widget tree stays exactly as it was before themes, while a host's toggle override still shows
--- on them. Touch mode does not change the answer, because the themed toggles are buttons
--- already, as the stock touch toggle is.
---@param resolved table|nil
---@param _ctx table|nil
---@return string
function Checkbox.Variant(resolved, _ctx)
    if type(resolved) ~= "table" or type(resolved.toggle) ~= "table" then
        return "stock"
    end
    local variant = resolved.toggle.variant
    if VARIANTS[variant] then
        return variant
    end
    return "stock"
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

------------------------------------------------------------------------------------------
-- Themed toggles
------------------------------------------------------------------------------------------

local function Alpha(color, a)
    color = color or { R = 1, G = 1, B = 1, A = 1 }
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local function SetShown(widget, on)
    pcall(function()
        widget:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_HIDDEN)
    end)
end

local function AddToOverlay(paint, overlay, widget, pad, halign, valign)
    local slot = overlay:AddChildToOverlay(widget)
    pcall(function()
        slot:SetPadding(paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
    return slot
end

local function Sized(umg, outer, name, content, w, h)
    local box = umg.Construct("/Script/UMG.SizeBox", outer, name)
    pcall(function()
        box:SetWidthOverride(w)
        box:SetHeightOverride(h)
        box:SetContent(content)
    end)
    return box
end

--- The multiplier for a toggle's own sizes, the one Paint.TextSize applies to text in touch mode,
--- so the control keeps its proportion to its label.
---@param config table|nil
---@return number
function Checkbox.Scale(config)
    if type(config) == "table" and config.pointerMode == "touch" then
        return config.touchFontScale or 1.75
    end
    return 1
end

local function ScaleRadius(r, m)
    if type(r) == "table" then
        return { (r[1] or 0) * m, (r[2] or 0) * m, (r[3] or 0) * m, (r[4] or 0) * m }
    end
    return r * m
end

-- The resolver derives radius as h / 2 so a switch is a pill. A box or chip with that radius is
-- a circle that reads as a radio button, so the derived value gives StyleLab's 3 instead. The
-- theme's own h is checked as well, because an item look that changes h keeps the radius the
-- theme derived from its h.
local function BoxRadius(t, themeH)
    local r = t.radius
    if r == nil then
        return 3
    end
    if type(r) == "number" and (r == (t.h or 20) / 2 or (themeH ~= nil and r == themeH / 2)) then
        return 3
    end
    return r
end

-- The spec runs without the game and cannot build a widget, so the module exposes this helper.
Checkbox._boxRadius = BoxRadius

--- A switch: a track and a knob for each of on and off. The off knob sits left and the on knob
--- right by slot alignment, so switching moves nothing, it only swaps which pair is shown.
local function BuildSwitch(ctx, name, t, square, m)
    local umg, paint = ctx.umg, ctx.paint
    local w, h = (t.w or 36) * m, (t.h or 20) * m
    local inset = 3 * m
    local knob = math.max(2, h - 2 * inset)
    local trackR = square and 3 * m or nil
    local knobR = square and 2 * m or nil
    local stack = umg.Construct("/Script/UMG.Overlay", ctx.contentBox, name .. "_Track")
    -- An off track with offEdge set is an outline only, as in Windows 11.
    local offTrack = paint.Box(stack, name .. "_TrackOff", {
        fill = t.offEdge and Alpha(t.offEdge, 0) or t.trackOff,
        outline = t.offEdge,
        width = t.offEdge and 1 or 0,
        radius = trackR,
        pill = not square,
    }, 0)
    local onTrack = paint.Box(stack, name .. "_TrackOn", { fill = t.trackOn, radius = trackR, pill = not square }, 0)
    local offKnob = Sized(umg, stack, name .. "_KnobOffSize",
        paint.Box(stack, name .. "_KnobOff", { fill = t.knobOff, radius = knobR, pill = not square }, 0), knob, knob)
    local onKnob = Sized(umg, stack, name .. "_KnobOnSize",
        paint.Box(stack, name .. "_KnobOn", { fill = t.knobOn, radius = knobR, pill = not square }, 0), knob, knob)
    AddToOverlay(paint, stack, offTrack, 0)
    AddToOverlay(paint, stack, onTrack, 0)
    AddToOverlay(paint, stack, offKnob, inset, H_LEFT, V_CENTER)
    AddToOverlay(paint, stack, onKnob, inset, H_RIGHT, V_CENTER)
    return Sized(umg, ctx.contentBox, name .. "_Size", stack, w, h), { onTrack, onKnob }, { offTrack, offKnob }
end

--- A tick drawn as two thin Borders turned by a render transform. A "✓" text would need the
--- glyph in the body font, and the engine's Roboto is not known to have it; a missing glyph
--- draws as an empty box.
local function BuildMark(ctx, name, color, m)
    local umg, paint = ctx.umg, ctx.paint
    local mark = umg.Construct("/Script/UMG.Overlay", ctx.contentBox, name .. "_Mark")
    -- The tick runs from (4, 10) down to (8, 14) and up to (16, 6) in the 20 by 20 box, scaled
    -- with the box. Each stroke is placed level around its midpoint and then turned about its centre.
    local strokes = {
        { w = 6, left = 3, top = 11, angle = 45 },
        { w = 12, left = 6, top = 9, angle = -45 },
    }
    for i, s in ipairs(strokes) do
        local line = paint.Box(mark, name .. "_Stroke" .. i, { fill = color }, 0)
        local sized = Sized(umg, mark, name .. "_StrokeSize" .. i, line, s.w * m, 2 * m)
        AddToOverlay(paint, mark, sized, { s.left * m, s.top * m, 0, 0 }, H_LEFT, V_TOP)
        pcall(function()
            sized:SetRenderTransformAngle(s.angle)
        end)
    end
    return mark
end

--- A check box: an off box, an on box and the tick shown with the on box.
local function BuildCheck(ctx, name, t, m, themeH)
    local umg, paint = ctx.umg, ctx.paint
    local radius = ScaleRadius(BoxRadius(t, themeH), m)
    local edgeWidth = t.checkEdgeWidth or 1
    local stack = umg.Construct("/Script/UMG.Overlay", ctx.contentBox, name .. "_Box")
    local off = paint.Box(stack, name .. "_BoxOff",
        { fill = t.checkOff, outline = t.checkEdge, width = edgeWidth, radius = radius }, 0)
    local on = paint.Box(stack, name .. "_BoxOn",
        { fill = t.checkOn, outline = t.checkEdgeOn, width = edgeWidth, radius = radius }, 0)
    local mark = BuildMark(ctx, name, t.checkMark, m)
    AddToOverlay(paint, stack, off, 0)
    AddToOverlay(paint, stack, on, 0)
    AddToOverlay(paint, stack, mark, 0)
    return Sized(umg, ctx.contentBox, name .. "_Size", stack, 20 * m, 20 * m), { on, mark }, { off }
end

--- A chip that reads On or Off. Each word is its own TextBlock in its own colour, so switching
--- only swaps visibility, as the shapes do.
local function BuildText(ctx, name, t, resolved, m, themeH)
    local umg, paint = ctx.umg, ctx.paint
    local p = resolved.palette or {}
    local body = resolved.body
    local radius = ScaleRadius(BoxRadius(t, themeH), m)
    local size = paint.TextSize(ctx.config, body and body.size, "fontItem")
    size = math.max(1, size - 1)
    local stack = umg.Construct("/Script/UMG.Overlay", ctx.contentBox, name .. "_Chip")
    local off = paint.Box(stack, name .. "_ChipOff", { fill = p.track, radius = radius }, 0)
    local on = paint.Box(stack, name .. "_ChipOn", { fill = p.accent, radius = radius }, 0)
    AddToOverlay(paint, stack, off, 0)
    AddToOverlay(paint, stack, on, 0)
    local function Word(suffix, caption, color)
        local word = umg.Construct("/Script/UMG.TextBlock", stack, name .. suffix)
        umg.StyleText(word, size, color, body)
        umg.SetLabelText(word, paint.Caption(caption, body))
        AddToOverlay(paint, stack, word, { 6 * m, 2 * m, 6 * m, 2 * m }, H_CENTER, V_CENTER)
        return word
    end
    local onWord = Word("_WordOn", "On", p.accentText)
    local offWord = Word("_WordOff", "Off", p.muted)
    return Sized(umg, ctx.contentBox, name .. "_Size", stack, 48 * m, 22 * m), { on, onWord }, { off, offWord }
end

local function ShowOn(ctrl, on)
    on = on == true
    if ctrl.shownOn == on then
        return
    end
    ctrl.shownOn = on
    for _, w in ipairs(ctrl.onShapes) do
        SetShown(w, on)
    end
    for _, w in ipairs(ctrl.offShapes) do
        SetShown(w, not on)
    end
end

--- Build a themed toggle: Button(clear, with a hover wash) > row(label, control). Returns the
--- root to add to the content box and the live control fields.
local function BuildShaped(ctx, variant, current, t)
    local umg, paint = ctx.umg, ctx.paint
    local item = ctx.item
    local resolved = ctx.config.resolved
    local name = ctx.namePrefix
    local m = Checkbox.Scale(ctx.config)
    local themeH = resolved.toggle and resolved.toggle.h

    local row = umg.Construct("/Script/UMG.HorizontalBox", ctx.contentBox, name .. "_Row")
    local label = umg.Construct("/Script/UMG.TextBlock", row, name .. "_Label")
    local body = resolved.body
    umg.StyleText(label, paint.TextSize(ctx.config, body and body.size, "fontItem"), nil, body)
    -- The control shows the state, so the caption is the label alone, without ": ON" or ": OFF".
    umg.SetLabelText(label, paint.Caption(item.label, body))

    local control, onShapes, offShapes
    if variant == "check" then
        control, onShapes, offShapes = BuildCheck(ctx, name, t, m, themeH)
    elseif variant == "text" then
        control, onShapes, offShapes = BuildText(ctx, name, t, resolved, m, themeH)
    else
        control, onShapes, offShapes = BuildSwitch(ctx, name, t, variant == "square", m)
    end

    local labelSlot = row:AddChildToHorizontalBox(label)
    pcall(function()
        labelSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        labelSlot:SetPadding(paint.Margin({ 6, 4, 8, 4 }))
        labelSlot:SetVerticalAlignment(V_CENTER)
    end)
    local controlSlot = row:AddChildToHorizontalBox(control)
    pcall(function()
        controlSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        controlSlot:SetPadding(paint.Margin({ 0, 4, 6, 4 }))
        controlSlot:SetHorizontalAlignment(H_RIGHT)
        controlSlot:SetVerticalAlignment(V_CENTER)
    end)

    -- The whole row is the click target. Its hover and pressed looks are a faint wash of the text
    -- colour in the button's shape, as StyleLab's toggle rows show.
    local p = resolved.palette or {}
    local b = resolved.button or {}
    local function Wash(a)
        return { fill = Alpha(p.text, a), radius = b.radius, pill = b.pill }
    end
    local states = { normal = Wash(0), hover = Wash(0.06), pressed = Wash(0.12) }
    local sb = paint.StateButton(ctx.contentBox, name .. "_Toggle", states, row, { pad = 0 })

    local ctrl = {
        root = sb.root,
        widget = sb.widget,
        label = label,
        labelWidget = label,
        paint = sb,
        onShapes = onShapes,
        offShapes = offShapes,
    }
    -- Every shape's first visibility is written here, before the tree is first shown.
    ShowOn(ctrl, current)
    return ctrl
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

    local resolved = ctx.config and ctx.config.resolved
    local variant = Checkbox.Variant(resolved, ctx)
    -- An item's own look may pick a variant, even on light and dark, because the host asked for it.
    if resolved ~= nil and item.look ~= nil and VARIANTS[item.look.variant] then
        variant = item.look.variant
    end
    if ctx.paint == nil then
        variant = "stock"
    end
    -- A look the style module rejects falls back to the stock toggle, so one bad look does not
    -- stop the build.
    local look = nil
    if variant ~= "stock" then
        local Style = require("ModMenu.core.style")
        local ok, merged = pcall(Style.ForItem, resolved, "toggle", item.look)
        if ok and type(merged) == "table" then
            look = merged
        else
            variant = "stock"
        end
    end

    if variant ~= "stock" then
        local shaped = BuildShaped(ctx, variant, current, look)
        umg.AddToContent(ctx, shaped.root)
        umg.AddItemPad(ctx, ctx.namePrefix .. "_Pad", 8)
        shaped.kind = "checkbox"
        shaped.sectionId = ctx.section.id
        shaped.item = item
        shaped.valueKey = vkey
        shaped.shaped = true
        shaped.variant = variant
        shaped.wasPressed = false
        table.insert(ctx.liveControls, shaped)
        return
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
    if ctrl.shaped then
        ShowOn(ctrl, nextOn)
    else
        ctx.umg.SetLabelText(ctrl.label, Caption(ctrl.item, nextOn))
        PaintToggle(ctrl, ctx, nextOn)
    end
    ctx.Input.DebugClick(path, ctrl, ctrl.widget)
    ctx.Input.SuppressPressEdge(ctrl)
    ctx.SafeCall(ctrl.item.onChange, nextOn)
    ctx.ReclaimMenuInput()
    ctx.Input.IgnoreClicks(2)
    return true
end

--- Native box: IsChecked. Touch button and themed toggles: the release click on the Button.
function Checkbox.poll(ctrl, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    if ctrl.shaped then
        ctx.paint.TrackPointer(ctrl.paint)
        if ctx.Input.ReleaseClick(ctrl, ctrl.widget) then
            FireToggle(ctrl, ctx, "release")
        end
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
    if not ctrl.asButton and not ctrl.shaped then
        return false
    end
    local consumed, fireNow = ctx.Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        return FireToggle(ctrl, ctx, "latch-hover")
    end
    return consumed
end

--- ItemState calls this when the toggle's state changes. The shell stops polling a disabled
--- control, so a hover or pressed wash shown at that moment would stay; a themed toggle shows its
--- normal look instead. The stock toggle keeps its behaviour and is left alone.
function Checkbox.onItemState(ctrl, enabled, _visible, ctx)
    if not ctrl.shaped or enabled then
        return
    end
    -- ItemState passes an empty context when the shell has no context maker, so paint is loaded here then.
    local paint = ctx ~= nil and ctx.paint or nil
    if paint == nil then
        local ok, mod = pcall(require, "ModMenu.core.paint")
        paint = ok and mod or nil
    end
    if paint ~= nil and ctrl.paint ~= nil then
        paint.ShowState(ctrl.paint, "normal")
    end
end

function Checkbox.apply(ctrl, value, ctx)
    if not ctx.IsValid(ctrl.widget) then
        return
    end
    local on = value and true or false
    if ctrl.shaped then
        ShowOn(ctrl, on)
        return
    end
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
