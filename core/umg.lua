--[[
  ModMenu.core.umg — StaticConstructObject helpers and common UMG controls.
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")

local M = {}

local defaults = {
    fontItem = 16,
    colors = nil, ---@type table|nil resolved in Init
}

function M.SetDefaults(opts)
    opts = opts or {}
    if opts.fontItem ~= nil then
        defaults.fontItem = opts.fontItem
    end
    if opts.colors ~= nil then
        defaults.colors = opts.colors
    end
end

local function Colors()
    return defaults.colors or Theme.Preset("light")
end

local lastScrollDebug = nil

--- Desktop: 8px. Touch: fat always-on track (finger). Drag-on-content is later —
--- MouseDown buttons steal the pointer, so the thumb has to be hittable.
--- Each setter is its own pcall: one failed UFunction must not skip thickness.
---@param scroll any
---@param config table|nil
function M.StyleScrollBox(scroll, config)
    if scroll == nil then
        return
    end
    local touch = config ~= nil and config.pointerMode == "touch"
    local thick = 8
    if touch then
        thick = 28
    end
    pcall(function()
        scroll:SetAnimateWheelScrolling(true)
    end)
    pcall(function()
        scroll:SetAlwaysShowScrollbar(touch == true)
    end)
    pcall(function()
        scroll:SetAllowOverscroll(touch == true)
    end)
    pcall(function()
        scroll:SetConsumeMouseWheel(1)
    end)
    pcall(function()
        if touch then
            scroll:SetAlwaysShowScrollbarTrack(true)
        end
    end)

    local vec = { X = thick, Y = thick }
    local applied = false
    if pcall(function()
        scroll:SetScrollbarThickness(vec)
    end) then
        applied = true
    elseif pcall(function()
        scroll.ScrollbarThickness = vec
    end) then
        applied = true
    elseif pcall(function()
        scroll.ScrollbarThickness.X = thick
        scroll.ScrollbarThickness.Y = thick
    end) then
        applied = true
    end

    -- FScrollBarStyle brushes often control how wide the thumb looks.
    pcall(function()
        local style = scroll.WidgetBarStyle
        if style == nil then
            return
        end
        local size = { X = thick, Y = thick }
        for _, key in ipairs({
            "VerticalBackgroundImage",
            "HorizontalBackgroundImage",
            "NormalThumbImage",
            "HoveredThumbImage",
            "DraggedThumbImage",
        }) do
            local brush = style[key]
            if brush ~= nil then
                pcall(function()
                    brush.ImageSize = size
                end)
            end
        end
        scroll.WidgetBarStyle = style
    end)

    pcall(function()
        scroll:SynchronizeProperties()
    end)

    local msg = string.format(
        "scroll thick=%d touch=%s thicknessSet=%s",
        thick,
        touch and "1" or "0",
        applied and "1" or "0"
    )
    if msg ~= lastScrollDebug then
        lastScrollDebug = msg
        Util.Debug(msg)
    end
end

local function FindClass(path)
    local cls = StaticFindObject(path)
    if not Util.IsValid(cls) then
        error("StaticFindObject failed: " .. path)
    end
    return cls
end

-- Widgets constructed since the module loaded, so the build log can report how many a build made.
local constructCount = 0

function M.Construct(classPath, outer, name)
    local cls = FindClass(classPath)
    local obj = StaticConstructObject(cls, outer, FName(name))
    if not Util.IsValid(obj) then
        error("StaticConstructObject failed: " .. classPath .. " as " .. name)
    end
    constructCount = constructCount + 1
    return obj
end

--- The number of widgets Construct has made since the module loaded. Paint.CountWidgets reads it.
---@return integer
function M.ConstructCount()
    return constructCount
end

--- A colour of the active legacy colour set by key, such as "buttonText", for code that styles a
--- widget the way this module's own controls do.
---@param key string
---@return table|nil
function M.Color(key)
    return Colors()[key]
end

--- Size and colour a TextBlock. With a text style from the resolved theme, Paint.Text writes it:
--- an explicit size wins, because callers compute it with Paint.TextSize, which already applies
--- the theme size, fontScale and touch scaling; with no size the style's size, then fontItem, is
--- used. An explicit color wins over the style's colour. With no text style this is the library's
--- original styling.
---@param textBlock any
---@param size number|nil
---@param color table|nil
---@param textSpec table|nil
function M.StyleText(textBlock, size, color, textSpec)
    if textSpec ~= nil then
        -- Paint requires this module, so it is loaded here at call time rather than at the top.
        local Paint = require("ModMenu.core.paint")
        local spec = {}
        for k, v in pairs(textSpec) do
            spec[k] = v
        end
        spec.color = color or textSpec.color or Colors().textPrimary
        Paint.Text(textBlock, spec, size or textSpec.size or defaults.fontItem)
        return
    end
    color = color or Colors().textPrimary
    pcall(function()
        if textBlock.Font then
            textBlock.Font.Size = size or defaults.fontItem
        end
        textBlock:SetColorAndOpacity({
            SpecifiedColor = color,
            ColorUseRule = 0,
        })
    end)
end

--- Do not gate on IsValid() — child TextBlocks inside Buttons often report invalid.
function M.SetLabelText(textBlock, str)
    if textBlock == nil then
        return false
    end
    local ok = pcall(function()
        textBlock:SetText(FText(tostring(str)))
    end)
    return ok == true
end

--- Soft-wrap TextBlock to its laid-out width (needed for long hint / status labels).
function M.EnableAutoWrap(textBlock)
    if textBlock == nil then
        return
    end
    pcall(function()
        textBlock:SetAutoWrapText(true)
    end)
    pcall(function()
        textBlock.AutoWrapText = true
    end)
end

--- HAlign_Fill so AutoWrapText uses the panel width instead of desired (unwrapped) width.
function M.FillVerticalSlot(slot)
    if slot == nil then
        return
    end
    pcall(function()
        slot:SetHorizontalAlignment(0) -- EHorizontalAlignment::HAlign_Fill
    end)
end

--- Remember a widget a build added for ctx.item, in ctx.nodes, so SetVisible and SetEnabled can reach it
--- later without a rebuild. A context with no nodes table records nothing.
---@param ctx table
---@param widget any
function M.RecordNode(ctx, widget)
    local nodes = ctx.nodes
    if nodes == nil or ctx.item == nil or widget == nil then
        return
    end
    local list = nodes[ctx.item]
    if list == nil then
        list = {}
        nodes[ctx.item] = list
    end
    list[#list + 1] = widget
end

function M.AddSpacer(parent, name, height)
    local spacer = M.Construct("/Script/UMG.Spacer", parent, name)
    pcall(function()
        spacer:SetSize({ X = 1, Y = height or 12 })
    end)
    parent:AddChildToVerticalBox(spacer)
    return spacer
end

--- Attach a widget to ctx.contentBox (VerticalBox or HorizontalBox via ctx.layout).
--- opts: fill (HBox fill), fillWeight, padLeft/Right/Top/Bottom, vAlign, fillVertical (VBox)
function M.AddToContent(ctx, widget, opts)
    opts = opts or {}
    local parent = ctx.contentBox
    local slot
    if ctx.layout == "horizontal" then
        slot = parent:AddChildToHorizontalBox(widget)
        pcall(function()
            if opts.fill then
                slot:SetSize({ SizeRule = 1, Value = opts.fillWeight or 1.0 })
            else
                slot:SetSize({ SizeRule = 0, Value = 0.0 })
            end
            slot:SetPadding({
                Left = opts.padLeft or 0,
                Top = opts.padTop or 0,
                Right = opts.padRight or 6,
                Bottom = opts.padBottom or 0,
            })
            -- EVerticalAlignment::VAlign_Center = 2
            slot:SetVerticalAlignment(opts.vAlign or 2)
        end)
    else
        slot = parent:AddChildToVerticalBox(widget)
        if opts.fillVertical then
            M.FillVerticalSlot(slot)
        end
    end
    M.RecordNode(ctx, widget)
    return slot
end

--- Trailing pad after an item. No-op in horizontal rows (slot padding handles gaps).
function M.AddItemPad(ctx, name, size)
    if ctx.layout == "horizontal" then
        return nil
    end
    local spacer = M.AddSpacer(ctx.contentBox, name, size or 8)
    M.RecordNode(ctx, spacer)
    return spacer
end

--- True when a resolved field style asks for the library's own field look. A missing style, as
--- under the spec runner or from a caller that passes none, is stock too.
---@param field table|nil
---@return boolean
function M.IsStockField(field)
    return field == nil or field.variant == nil or field.variant == "stock"
end

--- The themed field look for an item: its field style with the item's look merged in, the body
--- text style, and the text size to write. A config with no resolved theme, or a stock field,
--- gives nil, nil and the config's fontItem, so the caller draws the library's own field.
---@param config table
---@param look table|nil
---@param sizeKey string|nil the config size key, fontItem when nil
---@return table|nil field, table|nil textSpec, number size
function M.FieldLook(config, look, sizeKey)
    local key = sizeKey or "fontItem"
    local resolved = config and config.resolved
    if resolved == nil then
        return nil, nil, config and config[key] or defaults.fontItem
    end
    local Style = require("ModMenu.core.style")
    local field = Style.ForItem(resolved, "field", look)
    if M.IsStockField(field) then
        return nil, nil, config[key]
    end
    local Paint = require("ModMenu.core.paint")
    local textSpec = resolved.body
    return field, textSpec, Paint.TextSize(config, textSpec and textSpec.size, key)
end

--- Write a themed field's text and hint styles into an EditableTextBox, field by field into the
--- struct it owns and before it is first shown (field note 29).
local function StyleThemedEditable(edit, fontSize, field, textSpec)
    local fill = field.fill
    local slateFill = { SpecifiedColor = fill, ColorUseRule = 0 }
    local slateText = { SpecifiedColor = field.text, ColorUseRule = 0 }
    local slateHint = { SpecifiedColor = field.hint, ColorUseRule = 0 }
    local font = nil
    if textSpec ~= nil and textSpec.font ~= nil then
        local Paint = require("ModMenu.core.paint")
        font = Paint.Font(textSpec.font)
    end
    local typeface = textSpec ~= nil and textSpec.typeface or nil
    pcall(function()
        edit:SetForegroundColor(field.text)
    end)
    local style = nil
    pcall(function()
        style = edit.WidgetStyle
    end)
    if style == nil then
        return
    end
    pcall(function()
        style.ForegroundColor = slateText
    end)
    pcall(function()
        style.FocusedForegroundColor = slateText
    end)
    pcall(function()
        style.BackgroundColor = slateFill
    end)
    -- The wrapping Border is the visible field, so the box's own brushes draw nothing.
    for _, key in ipairs({ "BackgroundImageNormal", "BackgroundImageHovered", "BackgroundImageFocused",
        "BackgroundImageReadOnly" }) do
        pcall(function()
            local brush = style[key]
            brush.TintColor = slateFill
            brush.DrawAs = 0
        end)
    end
    for _, pair in ipairs({ { "TextStyle", slateText }, { "HintTextStyle", slateHint } }) do
        pcall(function()
            local ts = style[pair[1]]
            ts.ColorAndOpacity = pair[2]
            if fontSize then
                ts.Font.Size = fontSize
            end
            if font ~= nil then
                ts.Font.FontObject = font
            end
            if type(typeface) == "string" and typeface ~= "" then
                ts.Font.TypefaceFontName = FName(typeface)
            end
        end)
    end
    -- In-place writes are verified on Border, Button, Slider and ProgressBar but not on an
    -- EditableTextBox, so the struct is also assigned back, as the stock path has always done.
    pcall(function()
        edit.WidgetStyle = style
    end)
end

--- Style an EditableTextBox from theme field tokens.
--- The engine's default slate box is light-grey; WidgetStyle.BackgroundColor
--- often does not tint it. Hide those brushes and let the wrapping Border
--- (CreateLabeledEditable / dropdown search) be the visible fill.
--- field (optional) is a resolved field style and textSpec its text style. A stock or missing
--- field keeps the library's own styling from the legacy colours.
function M.StyleEditableTextBox(edit, fontSize, field, textSpec)
    if edit == nil then
        return
    end
    if not M.IsStockField(field) then
        StyleThemedEditable(edit, fontSize, field, textSpec)
        return
    end
    local colors = Colors()
    local fill = colors.fieldBg
    local dark = colors.fieldText
    local hint = colors.fieldHint
    local slateFill = { SpecifiedColor = fill, ColorUseRule = 0 }
    local slateText = { SpecifiedColor = dark, ColorUseRule = 0 }
    local slateHint = { SpecifiedColor = hint, ColorUseRule = 0 }

    pcall(function()
        edit:SetForegroundColor(dark)
    end)
    pcall(function()
        local style = edit.WidgetStyle
        if style == nil then
            return
        end
        pcall(function()
            style.ForegroundColor = slateText
        end)
        pcall(function()
            style.BackgroundColor = slateFill
        end)
        pcall(function()
            style.FocusedForegroundColor = slateText
        end)
        for _, key in ipairs({
            "BackgroundImageNormal",
            "BackgroundImageHovered",
            "BackgroundImageFocused",
            "BackgroundImageReadOnly",
        }) do
            local brush = style[key]
            if brush ~= nil then
                pcall(function()
                    brush.TintColor = slateFill
                    -- ESlateBrushDrawType::NoDrawType — Border behind the field is the fill.
                    brush.DrawAs = 0
                end)
            end
        end
        if style.TextStyle ~= nil then
            if style.TextStyle.ColorAndOpacity ~= nil then
                style.TextStyle.ColorAndOpacity = slateText
            end
            if style.TextStyle.Font ~= nil and style.TextStyle.Font.Size ~= nil and fontSize then
                style.TextStyle.Font.Size = fontSize
            end
        end
        if style.HintTextStyle ~= nil then
            if style.HintTextStyle.ColorAndOpacity ~= nil then
                style.HintTextStyle.ColorAndOpacity = slateHint
            end
            if style.HintTextStyle.Font ~= nil and style.HintTextStyle.Font.Size ~= nil and fontSize then
                style.HintTextStyle.Font.Size = fontSize
            end
        end
        edit.WidgetStyle = style
    end)
end

--- Labeled single-line field: HorizontalBox(label + SizeBox(Border(EditableTextBox))).
--- Field chrome follows the active theme (light fields on light, dark on dark).
--- opts.field (optional) is the item's resolved field style and opts.textSpec its text style. A
--- frame field draws its Border from the field's fill, outline, width and radius; a stock or
--- missing field keeps the library's own look. opts.bevel (optional) is a bevel drawn sunken around
--- the field's Border.
---@return any root, any editBox, any label
function M.CreateLabeledEditable(outer, namePrefix, caption, initialText, opts)
    opts = opts or {}
    local fontSize = opts.fontSize or defaults.fontItem
    local fieldWidth = opts.fieldWidth or 96
    local hint = opts.hint
    local field = not M.IsStockField(opts.field) and opts.field or nil
    local textSpec = field ~= nil and opts.textSpec or nil
    -- Paint requires this module, so it is loaded here at call time rather than at the top.
    local Paint = require("ModMenu.core.paint")

    local root = M.Construct("/Script/UMG.HorizontalBox", outer, namePrefix .. "_Row")

    local label = M.Construct("/Script/UMG.TextBlock", root, namePrefix .. "_Label")
    if textSpec ~= nil then
        M.StyleText(label, fontSize, nil, textSpec)
        M.SetLabelText(label, Paint.Caption(caption or "", textSpec))
    else
        M.StyleText(label, fontSize)
        M.SetLabelText(label, caption or "")
    end

    local labelHost = label
    if type(opts.labelWidth) == "number" and opts.labelWidth > 0 then
        local labelSize = M.Construct("/Script/UMG.SizeBox", root, namePrefix .. "_LabelSize")
        pcall(function()
            labelSize:SetWidthOverride(opts.labelWidth)
            labelSize:SetContent(label)
        end)
        labelHost = labelSize
    end

    local labelSlot = root:AddChildToHorizontalBox(labelHost)
    pcall(function()
        labelSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        labelSlot:SetPadding({ Left = 0, Top = 4, Right = 8, Bottom = 4 })
        labelSlot:SetVerticalAlignment(2)
    end)

    local sizeBox = M.Construct("/Script/UMG.SizeBox", root, namePrefix .. "_Size")
    pcall(function()
        sizeBox:SetWidthOverride(fieldWidth)
    end)

    local border
    if field ~= nil then
        -- A rounded or outlined frame is written into the Border's own brush; only a flat one is
        -- recoloured, inside Paint.Box (field note 30).
        border = Paint.Box(sizeBox, namePrefix .. "_Border", {
            fill = field.fill,
            outline = field.outline,
            width = field.width,
            radius = field.radius,
            pill = field.pill,
        }, { 8, 4, 8, 4 })
    else
        border = M.Construct("/Script/UMG.Border", sizeBox, namePrefix .. "_Border")
        pcall(function()
            border:SetBrushColor(Colors().fieldBg)
            border:SetPadding({ Left = 8, Top = 4, Right = 8, Bottom = 4 })
        end)
    end

    local edit = M.Construct("/Script/UMG.EditableTextBox", border, namePrefix .. "_Edit")
    pcall(function()
        edit:SetText(FText(tostring(initialText or "")))
        if hint ~= nil and hint ~= "" then
            edit:SetHintText(FText(tostring(hint)))
        end
    end)
    M.StyleEditableTextBox(edit, fontSize, field, textSpec)
    -- A short text inside the field, before the entry such as a currency sign or after it such as a unit.
    -- The field colours apply to it, because it sits on the field's own fill.
    local hasNote = (opts.prefix ~= nil and opts.prefix ~= "") or (opts.suffix ~= nil and opts.suffix ~= "")
    local content = edit
    if hasNote then
        content = M.Construct("/Script/UMG.HorizontalBox", border, namePrefix .. "_FieldRow")
        local function AddNote(noteName, text, padLeft, padRight)
            local note = M.Construct("/Script/UMG.TextBlock", content, namePrefix .. noteName)
            if field ~= nil then
                M.StyleText(note, fontSize, field.hint, textSpec)
            else
                M.StyleText(note, fontSize, Colors().fieldHint)
            end
            M.SetLabelText(note, text)
            local noteSlot = content:AddChildToHorizontalBox(note)
            pcall(function()
                noteSlot:SetSize({ SizeRule = 0, Value = 0.0 })
                noteSlot:SetPadding({ Left = padLeft, Top = 0, Right = padRight, Bottom = 0 })
                noteSlot:SetVerticalAlignment(2)
            end)
        end
        if opts.prefix ~= nil and opts.prefix ~= "" then
            AddNote("_Prefix", opts.prefix, 0, 2)
        end
        local editSlot = content:AddChildToHorizontalBox(edit)
        pcall(function()
            editSlot:SetSize({ SizeRule = 1, Value = 1.0 })
            editSlot:SetVerticalAlignment(2)
        end)
        if opts.suffix ~= nil and opts.suffix ~= "" then
            AddNote("_Suffix", opts.suffix, 2, 0)
        end
    end
    -- A field bevel goes around the Border, inside the size box. Without one the Border goes in alone.
    local framed = Paint.Bevelled(sizeBox, namePrefix .. "_FieldBevel", border, opts.bevel, true)
    pcall(function()
        border:SetContent(content)
        sizeBox:SetContent(framed)
    end)

    local fieldSlot = root:AddChildToHorizontalBox(sizeBox)
    pcall(function()
        if opts.fillField then
            fieldSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        else
            fieldSlot:SetSize({ SizeRule = 0, Value = 0.0 })
        end
        fieldSlot:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        fieldSlot:SetVerticalAlignment(2)
    end)

    -- The caller may add more children to the row, after the field, such as step buttons.
    if opts.extras ~= nil then
        opts.extras(root)
    end

    return root, edit, label
end

function M.CreateLabeledToggle(outer, namePrefix, caption, initialChecked, fontSize)
    local check = M.Construct("/Script/UMG.CheckBox", outer, namePrefix .. "_Check")
    local label = M.Construct("/Script/UMG.TextBlock", check, namePrefix .. "_Label")
    M.StyleText(label, fontSize or defaults.fontItem)
    M.SetLabelText(label, caption)
    check:SetContent(label)
    check:SetIsChecked(initialChecked and true or false)
    return check, label
end

function M.CreateTextButton(outer, namePrefix, caption, bgColor, textColor, fontSize)
    local button = M.Construct("/Script/UMG.Button", outer, namePrefix .. "_Btn")
    local label = M.Construct("/Script/UMG.TextBlock", button, namePrefix .. "_BtnLabel")
    M.StyleText(label, fontSize or defaults.fontItem, textColor or Colors().buttonText)
    M.SetLabelText(label, caption)
    pcall(function()
        button:SetContent(label)
        button:SetBackgroundColor(bgColor or Colors().buttonBg)
        -- MouseDown / touch-down so IsPressed is true on pointer-down
        -- (DownAndUp misses short taps).
        if button.SetClickMethod then
            button:SetClickMethod(1)
        end
        if button.SetTouchMethod then
            button:SetTouchMethod(1)
        end
    end)
    return button, label
end

--- A text button inside a Border. The Border is the visible fill, because a Button's own brushes
--- cannot be recoloured per state from Lua; widgets/button.lua makes the Button itself transparent
--- and repaints the Border. Returns fill, button, label, and the caller adds `fill` to a parent.
function M.CreateFilledButton(outer, namePrefix, caption, textColor, fontSize)
    local fill = M.Construct("/Script/UMG.Border", outer, namePrefix .. "_Fill")
    local button, label = M.CreateTextButton(fill, namePrefix, caption, nil, textColor, fontSize)
    pcall(function()
        fill:SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
        fill:SetContent(button)
    end)
    return fill, button, label
end

--- Give a button-like control its colours for each pointer state. `ctrl.widget` is the Button and
--- `ctrl.fill` the Border behind it. The Button is made fully transparent, so UMG's stock grey
--- hovered brush draws nothing and the Border carries the resting colour and every state after it.
---@param ctrl table
---@param normal table
---@param hover table
---@param pressed table
function M.SetFillColors(ctrl, normal, hover, pressed)
    ctrl.stateColors = { normal = normal, hover = hover, pressed = pressed }
    -- This paints the resting colour, so TrackPointer compares against the normal state from here.
    ctrl.lastState = "normal"
    pcall(function()
        if ctrl.widget ~= nil then
            ctrl.widget:SetBackgroundColor({ R = 1, G = 1, B = 1, A = 0 })
        end
        if ctrl.fill ~= nil then
            ctrl.fill:SetBrushColor(normal)
        end
    end)
end

--- SetFillColors with the hover and pressed colours derived from the resting fill, for controls
--- that have no button variant.
---@param ctrl table
---@param normal table
function M.SetFill(ctrl, normal)
    local hover, pressed = Theme.FillStates(normal)
    M.SetFillColors(ctrl, normal, hover, pressed)
end

local function IsTrue(value)
    return value == true or value == 1
end

--- Read the pointer state of the Button as "pressed", "hover" or "normal".
---@param widget any
---@return string
function M.PointerState(widget)
    local hovered, pressed = false, false
    pcall(function()
        hovered = IsTrue(widget:IsHovered())
    end)
    pcall(function()
        pressed = IsTrue(widget:IsPressed())
    end)
    if pressed then
        return "pressed"
    end
    if hovered then
        return "hover"
    end
    return "normal"
end

--- Repaint the Border behind a button when its pointer state changed since the last call.
--- A control with no fill or no colours is left alone.
---@param ctrl table
function M.TrackPointer(ctrl)
    if ctrl.widget == nil or ctrl.fill == nil or ctrl.stateColors == nil then
        return
    end
    local state = M.PointerState(ctrl.widget)
    if state == ctrl.lastState then
        return
    end
    ctrl.lastState = state
    pcall(function()
        ctrl.fill:SetBrushColor(ctrl.stateColors[state] or ctrl.stateColors.normal)
    end)
end

return M
