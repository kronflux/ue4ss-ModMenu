--[[
  ModMenu.shell.build — construct / destroy the UMG tree and rebuild section content.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Umg = require("ModMenu.core.umg")
local ItemState = require("ModMenu.core.itemstate")
local Theme = require("ModMenu.core.theme")
local Instance = require("ModMenu.core.instance")
local InputMode = require("ModMenu.core.inputmode")
local Cursor = require("ModMenu.core.cursor")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Dock = require("ModMenu.shell.dock")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")
local Confirm = require("ModMenu.shell.confirm")
local Tooltip = require("ModMenu.core.tooltip")
local Persist = require("ModMenu.core.persist")
local Paint = require("ModMenu.core.paint")
local Chrome = require("ModMenu.shell.chrome")
local Effects = require("ModMenu.shell.effects")
local Motion = require("ModMenu.core.motion")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local Construct = Umg.Construct
local StyleText = Umg.StyleText
local SetLabelText = Umg.SetLabelText
local AddSpacer = Umg.AddSpacer

local M = {}

-- Engine enum values for slot alignment.
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3
local V_FILL, V_TOP, V_CENTER, V_BOTTOM = 0, 1, 2, 3

local WHITE = { R = 1, G = 1, B = 1, A = 1 }

-- Header variants the shell draws. A preset naming any other variant gets the badge header, because
-- a header must always show the title and the Close button.
local HEADER_VARIANTS = {
    stock = true, badge = true, plain = true, rule = true, bar = true, tape = true, strip = true,
    window = true, mac = true, xpbar = true, classic = true,
}

-- Variants drawn as a band across the top of the panel, outside the padded scroll area.
local BAND_VARIANTS = {
    bar = true, tape = true, strip = true, window = true, xpbar = true, classic = true,
}

-- Variants whose title row lives in S.headerBand and is rebuilt with the content: the bar and the
-- window frames. The tape and strip bands are decoration only, and their header is a content row.
local function InBandVariant(variant)
    return variant == "bar" or Chrome.BAND[variant] == true
end

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

--- A shallow copy of a text style with another colour, so a header can tint its title without
--- changing the resolved style that every later build reads.
local function WithColor(spec, color)
    local out = {}
    for k, v in pairs(spec or {}) do
        out[k] = v
    end
    out.color = color
    return out
end

local function Radii(radius)
    if type(radius) == "table" then
        return { radius[1] or 0, radius[2] or 0, radius[3] or 0, radius[4] or 0 }
    end
    local r = tonumber(radius) or 0
    return { r, r, r, r }
end

local function LargestRadius(radius)
    local r = Radii(radius)
    return math.max(r[1], r[2], r[3], r[4])
end

local function OverlayAdd(overlay, widget, pad, halign, valign)
    local slot = nil
    pcall(function()
        slot = overlay:AddChildToOverlay(widget)
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
    return slot
end

local function HBoxAdd(row, widget, fill, pad, valign)
    pcall(function()
        local slot = row:AddChildToHorizontalBox(widget)
        slot:SetSize({ SizeRule = fill and 1 or 0, Value = fill and 1.0 or 0.0 })
        slot:SetPadding(Paint.Margin(pad))
        slot:SetVerticalAlignment(valign or V_CENTER)
    end)
end

local function VBoxAdd(box, widget, pad, halign)
    pcall(function()
        local slot = box:AddChildToVerticalBox(widget)
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
    end)
end

--- A SizeBox around a child, for the fixed sizes of bands, brackets and the badge.
local function Sized(outer, name, child, w, h)
    local size = Construct("/Script/UMG.SizeBox", outer, name)
    pcall(function()
        if w ~= nil then
            size:SetWidthOverride(w)
        end
        if h ~= nil then
            size:SetHeightOverride(h)
        end
    end)
    pcall(function()
        size:SetContent(child)
    end)
    return size
end

--- Returns the panel's inner padding: spacing.panelPad on all four sides when the host set it,
--- otherwise the resolved theme's panel padding, so that Init without panelPad keeps the theme's layout.
function M.PanelPadding(config)
    local pad = config.spacing and config.spacing.panelPad
    if pad ~= nil then
        return { Left = pad, Top = pad, Right = pad, Bottom = pad }
    end
    local resolved = config.resolved
    if type(resolved) == "table" and type(resolved.panel) == "table" and resolved.panel.pad ~= nil then
        return Paint.Margin(resolved.panel.pad)
    end
    -- A config built before themes existed has no resolved style; the legacy table still knows light and dark.
    return Theme.PadPanel(config)
end

--- The header variant to draw for a resolved style: stock without a style, badge for a name this stage does not draw.
---@param resolved table|nil
---@return string
function M.HeaderVariant(resolved)
    local header = type(resolved) == "table" and resolved.header or nil
    if type(header) ~= "table" or header.variant == nil then
        return "stock"
    end
    if HEADER_VARIANTS[header.variant] then
        return header.variant
    end
    return "badge"
end

--- True when the panel is the library's original one: square, no outline width, no blur, shadow,
--- rim or corner brackets. Light and dark are such panels, so they keep today's two Borders.
---@param panel table|nil
---@return boolean
function M.IsStockPanel(panel, motion)
    if type(panel) ~= "table" then
        return true
    end
    if not Paint.IsFlat(panel) then
        return false
    end
    if (tonumber(panel.blur) or 0) > 0 then
        return false
    end
    if Paint.ShadowDepth(panel) > 0 then
        return false
    end
    -- A status bar is drawn inside the themed panel's stack.
    if type(panel.statusBar) == "table" then
        return false
    end
    -- Scanlines, the sweep and the glints are drawn into the themed panel's body.
    if panel.scanlines == true or (tonumber(panel.scanlines) or 0) > 0 or panel.sweep == true
        or (type(motion) == "table" and motion.sparkle == true) then
        return false
    end
    return panel.rim ~= true and panel.corners ~= true
end

--- Count the registered items across sections, with the children of rows and folds, for the build log line.
---@param sections table
---@return integer
function M.CountItems(sections)
    local function Count(items)
        local n = 0
        for _, item in ipairs(items or {}) do
            n = n + 1
            if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
                n = n + Count(item.items)
            end
        end
        return n
    end
    local total = 0
    for _, section in ipairs(sections or {}) do
        total = total + Count(section.items)
    end
    return total
end

------------------------------------------------------------------------------------------
-- Header
------------------------------------------------------------------------------------------

-- Decorative parts that already failed this session, so each failure is logged once and not on every build.
local failedParts = {}

--- Build one decorative part of the panel guarded. Umg.Construct throws by design, and a blur, rim,
--- bracket, shadow or window frame that fails must leave a usable panel rather than abort the whole shell.
local function Decoration(part, fn)
    local ok, err = pcall(fn)
    if not ok and not failedParts[part] then
        failedParts[part] = true
        Log("panel " .. part .. " failed, drawn without it: " .. tostring(err))
    end
    return ok
end

local function HintText(config)
    local keyName = tostring(config.keyHint or config.keyName or "F6")
    local hintText = "[" .. keyName .. "] toggle menu"
    if type(config.consoleCommand) == "string" and config.consoleCommand ~= "" then
        hintText = hintText .. " · " .. config.consoleCommand
    end
    return hintText
end

--- The library's original header: a title row with a flat Close button, then the hint line.
--- A host's title or hint override takes effect here too, written into the same TextBlock, so the
--- widget tree stays the stock one; without an override the text is styled exactly as before themes.
---@return table|nil the resolved text style of typeName when the host overrides it, else nil
local function OverriddenText(config, resolved, typeName)
    if resolved == nil or type(config.style) ~= "table" or config.style[typeName] == nil then
        return nil
    end
    return resolved[typeName]
end

-- Write a stock header line: through the overridden text style when there is one, else as before themes.
local function StockText(block, config, text, spec, sizeKey)
    if spec ~= nil then
        Paint.Text(block, spec, Paint.TextSize(config, spec.size, sizeKey))
        SetLabelText(block, Paint.Caption(text, spec))
    else
        StyleText(block, config[sizeKey])
        SetLabelText(block, text)
    end
end

local function StockHeader(S, row, suffix, resolved)
    local config = S.config
    local title = Construct("/Script/UMG.TextBlock", row, "ModMenu_Title_" .. suffix)
    StockText(title, config, config.title, OverriddenText(config, resolved, "title"), "fontTitle")
    local titleSlot = row:AddChildToHorizontalBox(title)
    pcall(function()
        titleSlot:SetSize({ SizeRule = 1, Value = 1.0 })
        titleSlot:SetVerticalAlignment(2)
    end)

    -- Title-row Close: same path as the toggle key. Opt out with showClose = false.
    if config.showClose ~= false then
        local closeFill, closeBtn, closeLbl = Umg.CreateFilledButton(
            row,
            "ModMenu_Close_" .. suffix,
            "Close"
        )
        local closeSlot = row:AddChildToHorizontalBox(closeFill)
        pcall(function()
            closeSlot:SetSize({ SizeRule = 0, Value = 0.0 })
            closeSlot:SetPadding({ Left = 8, Top = 0, Right = 0, Bottom = 0 })
            closeSlot:SetVerticalAlignment(2)
        end)
        local closeCtrl = {
            kind = "close",
            widget = closeBtn,
            fill = closeFill,
            label = closeLbl,
            role = "close",
            wasPressed = false,
        }
        Umg.SetFill(closeCtrl, Theme.Of(config).buttonBg)
        table.insert(S.liveControls, closeCtrl)
    end

    local hint = Construct("/Script/UMG.TextBlock", S.contentBox, "ModMenu_Hint_" .. suffix)
    StockText(hint, config, HintText(config), OverriddenText(config, resolved, "hint"), "fontHint")
    S.contentBox:AddChildToVerticalBox(hint)
end

local function ThemedText(outer, name, text, spec, size)
    local block = Construct("/Script/UMG.TextBlock", outer, name)
    Paint.Text(block, spec, size)
    SetLabelText(block, Paint.Caption(text, spec))
    return block
end

--- The header title, with the ghost copies of a glitching look. A title that cannot get its ghosts is
--- drawn plain, under another name so that it never meets the half-built one.
local function TitleWidget(S, outer, text, spec, size, resolved, suffix)
    local widget = nil
    Decoration("title ghosts", function()
        widget = Effects.Title(S, outer, text, spec, size, resolved, suffix)
    end)
    if widget == nil then
        widget = ThemedText(outer, "ModMenu_TitleFallback_" .. suffix, text, spec, size)
        if S.fx == nil then
            Effects.Reset(S)
        end
        S.fx.title = widget
        S.fx.ghosts = {}
    end
    return widget
end

--- The pointer looks of the Close button. On a coloured band (tint given) it is a clear wash of the
--- band's text colour, as StyleLab's close button is; elsewhere it takes the button style's default
--- role, with an edge only when the preset gives that role one.
local function CloseStates(resolved, tint)
    local b = resolved.button or {}
    local shape = function(fill)
        return { fill = fill, radius = b.radius, pill = b.pill }
    end
    if tint ~= nil then
        return {
            normal = shape(Alpha(tint, 0)),
            hover = shape(Alpha(tint, 0.14)),
            pressed = shape(Alpha(tint, 0.24)),
        }, tint
    end
    local role = (b.roles and b.roles.default) or {}
    local states = { normal = shape(role.fill or Theme.Of(nil).buttonBg) }
    if role.hover ~= nil then
        states.hover = shape(role.hover)
    end
    if role.pressed ~= nil then
        states.pressed = shape(role.pressed)
    end
    if role.edge ~= nil then
        states.edge = { outline = role.edge, width = math.max(1, tonumber(b.width) or 1) }
    end
    return states, role.text
end

local function ThemedClose(S, row, resolved, suffix, tint)
    local config = S.config
    if config.showClose == false then
        return
    end
    local b = resolved.button or {}
    local states, textColor = CloseStates(resolved, tint)
    local body = resolved.body or {}
    local ctrl = Paint.StateButton(row, "ModMenu_Close_" .. suffix, states, "Close", {
        color = textColor,
        size = Paint.TextSize(config, b.size, "fontItem"),
        textSpec = { font = body.font, typeface = b.typeface, spacing = b.spacing, upper = b.upper },
        pad = { 12, 4, 12, 4 },
    })
    HBoxAdd(row, ctrl.root, false, { 8, 0, 0, 0 }, tint ~= nil and V_TOP or V_CENTER)
    ctrl.kind = "close"
    ctrl.role = "close"
    ctrl.wasPressed = false
    table.insert(S.liveControls, ctrl)
end

--- A square badge holding the title's first letter in the accent colour. StyleLab shows an icon
--- there; the library has no icon textures, and the letter keeps the badge tied to the menu.
local function Badge(S, row, resolved, suffix)
    local header = resolved.header
    local panel = resolved.panel or {}
    local box = Paint.Box(row, "ModMenu_Badge_" .. suffix, {
        fill = header.badgeFill,
        radius = math.min(8, LargestRadius(panel.radius)),
    }, 0)
    local first = tostring(S.config.title or ""):match("[%w]") or "M"
    local letter = ThemedText(box, "ModMenu_BadgeLetter_" .. suffix, first:upper(),
        WithColor(resolved.title, resolved.palette.accent), Paint.TextSize(S.config, resolved.title.size, "fontTitle"))
    pcall(function()
        local slot = box:SetContent(letter)
        box:SetHorizontalAlignment(H_CENTER)
        box:SetVerticalAlignment(V_CENTER)
        if slot ~= nil then
            slot:SetHorizontalAlignment(H_CENTER)
            slot:SetVerticalAlignment(V_CENTER)
        end
    end)
    HBoxAdd(row, Sized(row, "ModMenu_BadgeSize_" .. suffix, box, 36, 36), false, { 0, 0, 12, 0 }, V_CENTER)
end

local function HeaderLine(S, name, color, w, h, pad, halign)
    local line = Paint.Box(S.contentBox, name, { fill = color }, 0)
    VBoxAdd(S.contentBox, Sized(S.contentBox, name .. "_Size", line, w, h), pad, halign)
end

--- Undo a window frame that failed part way: drop the controls it registered and the widgets it
--- put in the row, so the plain header drawn instead owns the row alone.
local function DropFailedFrame(S, row, first)
    for i = #S.liveControls, first, -1 do
        S.liveControls[i] = nil
    end
    pcall(function()
        row:ClearChildren()
    end)
end

--- Draw the header into row: the title, the Close button and the hint line, in the resolved
--- header variant. For bar, row sits in the band across the top of the panel; for every other
--- variant it is the first row of the content, and the hint and any rule go under it.
---@param S table
---@param row any HorizontalBox
---@param resolved table|nil
---@param suffix string
function M.Header(S, row, resolved, suffix)
    local variant = M.HeaderVariant(resolved)
    if variant == "stock" then
        StockHeader(S, row, suffix, resolved)
        return
    end
    ---@cast resolved table
    local config = S.config
    local titleSize = Paint.TextSize(config, resolved.title.size, "fontTitle")
    local hintSize = Paint.TextSize(config, resolved.hint.size, "fontHint")
    local palette = resolved.palette
    local header = resolved.header

    -- A bar or window-frame header is drawn only in the band Create built for it; without that band
    -- it falls back to plain.
    local inBand = InBandVariant(variant) and IsValid(S.headerBand)
    if InBandVariant(variant) and not inBand then
        variant = "plain"
    end

    -- The window frames keep the hint as the first line of the content, under the title bar.
    local function FrameHint(pad, halign)
        VBoxAdd(S.contentBox, ThemedText(S.contentBox, "ModMenu_Hint_" .. suffix, HintText(config), resolved.hint, hintSize),
            pad, halign)
    end

    if inBand and variant ~= "bar" then
        local first = #S.liveControls + 1
        if Decoration("window frame", function()
            Chrome.BandRow(S, row, resolved, suffix)
        end) then
            FrameHint({ 0, 8, 0, 10 })
            return
        end
        DropFailedFrame(S, row, first)
        variant = "plain"
    elseif variant == "mac" then
        local first = #S.liveControls + 1
        if Decoration("window frame", function()
            Chrome.MacHeader(S, row, resolved, suffix)
        end) then
            FrameHint({ 0, 0, 0, 10 }, H_CENTER)
            if header.line ~= nil then
                HeaderLine(S, "ModMenu_HeaderLine_" .. suffix, header.line, nil, 1, { 0, 0, 0, 10 }, H_FILL)
            end
            return
        end
        DropFailedFrame(S, row, first)
        variant = "plain"
    end

    if inBand and variant == "bar" then
        local barText = M.BarColors(resolved)
        local titles = Construct("/Script/UMG.VerticalBox", row, "ModMenu_Titles_" .. suffix)
        VBoxAdd(titles, TitleWidget(S, titles, config.title, WithColor(resolved.title, barText), titleSize,
            resolved, suffix), 0)
        VBoxAdd(titles, ThemedText(titles, "ModMenu_Hint_" .. suffix, HintText(config),
            WithColor(resolved.hint, Alpha(barText, 0.8)), hintSize), { 0, 2, 0, 0 })
        -- With a cursor the titles keep their own width and the cursor follows them, as in StyleLab;
        -- without one the titles fill the row, as before.
        local cursor = nil
        Decoration("cursor", function()
            cursor = Effects.Cursor(S, row, resolved, suffix)
        end)
        HBoxAdd(row, titles, cursor == nil, 0, V_TOP)
        if cursor ~= nil then
            HBoxAdd(row, cursor, false, { 8, 2, 0, 0 }, V_TOP)
            HBoxAdd(row, Construct("/Script/UMG.Spacer", row, "ModMenu_CursorGap_" .. suffix), true, 0, V_TOP)
        end
        ThemedClose(S, row, resolved, suffix, barText)
        return
    end

    -- A strip band keeps StyleLab's badge header under it; tape has a plain one.
    if variant == "badge" or variant == "strip" then
        Badge(S, row, resolved, suffix)
    end
    HBoxAdd(row, TitleWidget(S, row, config.title, resolved.title, titleSize, resolved, suffix), true, 0, V_CENTER)
    ThemedClose(S, row, resolved, suffix, nil)

    if variant == "rule" then
        HeaderLine(S, "ModMenu_HeaderRule_" .. suffix, palette.accent, 56, 6, { 0, 6, 0, 6 }, H_LEFT)
    end
    VBoxAdd(S.contentBox, ThemedText(S.contentBox, "ModMenu_Hint_" .. suffix, HintText(config), resolved.hint, hintSize),
        { 0, variant == "rule" and 0 or 4, 0, 0 })
    if variant ~= "rule" then
        HeaderLine(S, "ModMenu_HeaderLine_" .. suffix, header.line, nil, 1, { 0, 10, 0, 0 }, H_FILL)
    end
end

--- The bar header's text colour and fill: the header's own fill and text when the preset gives the
--- header a visible fill, otherwise the accent and accent text, as StyleLab's bar is drawn.
---@param resolved table
---@return table text, table fill
function M.BarColors(resolved)
    local header = resolved.header or {}
    local palette = resolved.palette
    if type(header.fill) == "table" and (header.fill.A or 0) > 0 then
        return header.text or palette.text, header.fill
    end
    return palette.accentText, palette.accent
end

------------------------------------------------------------------------------------------
-- Panel
------------------------------------------------------------------------------------------

--- The band across the top of a themed panel for the bar, tape and strip headers, or nil.
--- The bar's content is set by each content build, so a new title or hint shows without a rebuild.
local function TopBand(S, stack, resolved, suffix)
    local variant = M.HeaderVariant(resolved)
    if not BAND_VARIANTS[variant] then
        return nil
    end
    local header = resolved.header
    local palette = resolved.palette
    local radii = Radii(resolved.panel.radius)
    local top = { radii[1], radii[2], 0, 0 }
    if Chrome.BAND[variant] then
        -- A frame that cannot be built leaves no band, and the header is drawn plain.
        local built = nil
        Decoration("window frame band", function()
            built = Chrome.TopBand(S, stack, resolved, suffix)
        end)
        if built == nil then
            S.headerBand = nil
        end
        return built
    end
    if variant == "bar" then
        local _, fill = M.BarColors(resolved)
        local pad = M.PanelPadding(S.config)
        local bar = Paint.Box(stack, "ModMenu_HeaderBand_" .. suffix, { fill = fill, radius = top },
            { pad.Left, 12, math.max(0, pad.Right - 6), 12 })
        S.headerBand = bar
        return bar
    end
    if variant == "tape" then
        -- Hazard tape: thirty equal blocks alternating the accent and a near-black.
        local row = Construct("/Script/UMG.HorizontalBox", stack, "ModMenu_HeaderTape_" .. suffix)
        local alt = header.tapeAlt or Alpha({ R = 0, G = 0, B = 0 }, 0.85)
        for i = 1, 30 do
            local block = Paint.Box(row, "ModMenu_HeaderTape_" .. i .. "_" .. suffix,
                { fill = (i % 2 == 1) and palette.accent or alt }, 0)
            pcall(function()
                local slot = row:AddChildToHorizontalBox(block)
                slot:SetSize({ SizeRule = 1, Value = 1.0 })
                slot:SetVerticalAlignment(V_FILL)
            end)
        end
        return Sized(stack, "ModMenu_HeaderTapeSize_" .. suffix, row, nil, tonumber(header.tape) or 8)
    end
    local strip = Paint.Box(stack, "ModMenu_HeaderStrip_" .. suffix, { fill = palette.accent, radius = top }, 0)
    return Sized(stack, "ModMenu_HeaderStripSize_" .. suffix, strip, nil, tonumber(header.strip) or 4)
end

--- An L-shaped accent bracket for one corner of the panel.
local function Bracket(outer, name, color, halign, valign)
    local corner = Construct("/Script/UMG.Overlay", outer, name)
    local across = Paint.Box(corner, name .. "_H", { fill = color }, 0)
    local down = Paint.Box(corner, name .. "_V", { fill = color }, 0)
    OverlayAdd(corner, Sized(corner, name .. "_HSize", across, 18, 2), 0, halign, valign)
    OverlayAdd(corner, Sized(corner, name .. "_VSize", down, 2, 18), 0, halign, valign)
    return Sized(outer, name .. "_Size", corner, 18, 18)
end

--- The original panel: a fill Border with the padding inside a 1 px outline Border, both recoloured flat.
local function StockPanel(S, suffix)
    local config = S.config
    local canvas = S.menuCanvas
    local colors = Theme.Of(config)
    local fill = Construct("/Script/UMG.Border", canvas, "ModMenu_Border_" .. suffix)
    S.panelBorder = fill
    pcall(function()
        fill:SetBrushColor(colors.panelBg)
        fill:SetPadding(M.PanelPadding(config))
    end)

    -- Always wrap in a 1px outline. Light uses panelBg so the edge is invisible.
    local outline = Construct("/Script/UMG.Border", canvas, "ModMenu_Outline_" .. suffix)
    S.panelOutline = outline
    pcall(function()
        outline:SetBrushColor(colors.panelBorder)
        outline:SetPadding({ Left = 1, Top = 1, Right = 1, Bottom = 1 })
        outline:SetContent(fill)
    end)

    -- ScrollBox fills the docked panel so long section lists are reachable.
    local scroll = Construct("/Script/UMG.ScrollBox", fill, "ModMenu_Scroll_" .. suffix)
    S.menuScroll = scroll
    fill:SetContent(scroll)
    return outline, scroll
end

--- The panel body with its shadow behind it, or the body alone when there is no shadow or the shadow
--- fails. The shadow wrapper is built in full before the body joins it, so a failure never leaves the
--- body parented under a half-built wrapper; the layout matches Paint.WithShadow.
local function ShadowWrap(canvas, name, panel, body)
    if Paint.ShadowDepth(panel) <= 0 then
        return body
    end
    local wrap, depth = nil, 0
    Decoration("shadow", function()
        local root = Construct("/Script/UMG.Overlay", canvas, name)
        local layer, d = Paint.Shadow(root, name .. "_Shadow", panel, panel.radius)
        if layer == nil then
            return
        end
        local slot = root:AddChildToOverlay(layer)
        pcall(function()
            slot:SetPadding(Paint.Margin(0))
            slot:SetHorizontalAlignment(H_FILL)
            slot:SetVerticalAlignment(V_FILL)
        end)
        wrap, depth = root, d
    end)
    if wrap == nil then
        return body
    end
    if OverlayAdd(wrap, body, { 0, 0, depth, depth }) == nil then
        -- The add failed, so the body is detached from any partial parent and used as the root itself.
        pcall(function()
            body:RemoveFromParent()
        end)
        return body
    end
    return wrap
end

--- A themed panel: an Overlay holding the blur, the panel shape with an optional top band and the
--- padded scroll area, the rim lines and the corner brackets, wrapped with its shadow.
local function ThemedPanel(S, resolved, suffix)
    local config = S.config
    local canvas = S.menuCanvas
    local p = resolved.panel
    local palette = resolved.palette

    -- The panel shape and its padding live in this build, not in S.panelBorder and S.panelOutline:
    -- OnConfigChanged recolours those with SetBrushColor and pads the fill Border, which would draw
    -- a rim on a rounded shape (field note 30) and pad the panel twice.
    S.panelBorder = nil
    S.panelOutline = nil

    local body = Construct("/Script/UMG.Overlay", canvas, "ModMenu_PanelBody_" .. suffix)

    -- The blur goes under the panel shape, at half the panel's radius and inset from its edge (field note 32).
    if (tonumber(p.blur) or 0) > 0 then
        Decoration("blur", function()
            local base = p.radius
            if type(base) ~= "table" and p.blurRadius ~= nil then
                -- Paint.Blur halves the radius it is given, so a preset's own blurRadius is passed doubled.
                base = (tonumber(p.blurRadius) or 0) * 2
            end
            local blur, inset = Paint.Blur(body, "ModMenu_PanelBlur_" .. suffix, p.blur, base)
            if blur ~= nil then
                OverlayAdd(body, blur, tonumber(p.blurInset) or inset)
            end
        end)
    end

    local box = Paint.Box(body, "ModMenu_Border_" .. suffix,
        { fill = p.fill, outline = p.outline, width = p.width, radius = p.radius }, 0)
    local stack = Construct("/Script/UMG.VerticalBox", box, "ModMenu_PanelStack_" .. suffix)
    pcall(function()
        box:SetContent(stack)
    end)

    local band = TopBand(S, stack, resolved, suffix)
    if band ~= nil then
        VBoxAdd(stack, band, tonumber(p.bandInset) or 0)
    end

    -- ScrollBox fills the docked panel so long section lists are reachable.
    local scroll = Construct("/Script/UMG.ScrollBox", stack, "ModMenu_Scroll_" .. suffix)
    S.menuScroll = scroll
    pcall(function()
        local slot = stack:AddChildToVerticalBox(scroll)
        -- The padding is read once per build. An Init that changes only spacing.panelPad keeps the look's key,
        -- so on a themed panel the new padding shows at the next shell rebuild (accepted for stage 1).
        slot:SetPadding(M.PanelPadding(config))
        slot:SetSize({ SizeRule = 1, Value = 1.0 })
    end)

    -- A status bar closes the stack under the scroll area, as on Windows XP forms.
    if type(p.statusBar) == "table" then
        Decoration("status bar", function()
            Chrome.StatusBar(S, stack, resolved, suffix)
        end)
    end

    -- A raised bevel is drawn over the panel shape as 1-unit lines, as StyleLab's Bevel does. A bevel
    -- that fails leaves the plain panel shape.
    local shape = box
    if type(p.bevel) == "table" then
        local ok = Decoration("bevel", function()
            shape = Paint.Bevelled(body, "ModMenu_PanelBevel_" .. suffix, box, p.bevel, false)
        end)
        if not ok then
            pcall(function()
                box:RemoveFromParent()
            end)
            shape = box
        end
    end
    OverlayAdd(body, shape, 0)

    -- The drawn effects sit over the panel shape and under the rim, in StyleLab's order.
    Effects.Build(S, body, resolved, suffix, Decoration)

    if p.rim == true then
        Decoration("rim", function()
            -- A light line inside the top edge and a dark one inside the bottom edge, kept clear of the corners.
            local inset = math.max(4, LargestRadius(p.radius))
            local light = Paint.Box(body, "ModMenu_RimLight_" .. suffix, { fill = p.rimLight or Alpha(WHITE, 0.7) }, 0)
            local dark = Paint.Box(body, "ModMenu_RimDark_" .. suffix,
                { fill = p.rimDark or Alpha({ R = 0, G = 0, B = 0 }, 0.25) }, 0)
            OverlayAdd(body, Sized(body, "ModMenu_RimLightSize_" .. suffix, light, nil, 1), { inset, 1, inset, 0 }, H_FILL, V_TOP)
            OverlayAdd(body, Sized(body, "ModMenu_RimDarkSize_" .. suffix, dark, nil, 1), { inset, 0, inset, 1 }, H_FILL, V_BOTTOM)
        end)
    end

    if p.corners == true then
        local corners = {
            { "TL", H_LEFT, V_TOP }, { "TR", H_RIGHT, V_TOP },
            { "BL", H_LEFT, V_BOTTOM }, { "BR", H_RIGHT, V_BOTTOM },
        }
        for _, c in ipairs(corners) do
            Decoration("corner bracket", function()
                local bracket = Bracket(body, "ModMenu_Corner" .. c[1] .. "_" .. suffix, palette.accent, c[2], c[3])
                OverlayAdd(body, bracket, 0, c[2], c[3])
            end)
        end
    end

    -- The outermost widget, which the shadow wraps, is kept for the effects and the motion to move.
    local root = ShadowWrap(canvas, "ModMenu_PanelShadow_" .. suffix, p, body)
    S.panelRoot = root
    S.fx.root = root
    return root, scroll
end

--- Build the panel under S.menuCanvas from the resolved style and return the widget to add to the
--- canvas and the ScrollBox that holds the content. A stock panel with a stock header keeps the
--- library's original two Borders; any other look is drawn with Paint.
---@param S table
---@param resolved table|nil
---@param suffix string|nil the shell name suffix; Create passes its own
---@return any root, any scroll
function M.Panel(S, resolved, suffix)
    suffix = suffix or Instance.ShellNameSuffix(S.config)
    S.headerBand = nil
    S.panelRoot = nil
    Effects.Reset(S)
    local panel = type(resolved) == "table" and resolved.panel or nil
    local motion = type(resolved) == "table" and resolved.motion or nil
    if M.IsStockPanel(panel, motion) and not BAND_VARIANTS[M.HeaderVariant(resolved)] then
        local outline, scroll = StockPanel(S, suffix)
        S.panelRoot = outline
        S.fx.root = outline
        return outline, scroll
    end
    ---@cast resolved table
    return ThemedPanel(S, resolved, suffix)
end

--- A section's description: one line of muted text under its title.
local function AddDescription(S, section, contentBox, suffix)
    if type(section.description) ~= "string" or section.description == "" then
        return
    end
    local text = Construct("/Script/UMG.TextBlock", contentBox, string.format("ModMenu_SecDesc_%s_%s", section.id, suffix))
    -- The hint size in the muted colour darkened by a third, so the description reads as a quieter line
    -- than the title rather than in nearly the title's colour.
    StyleText(text, S.config.fontHint, Theme.Shade(Theme.Of(S.config).textMuted, -0.35))
    SetLabelText(text, section.description)
    Umg.EnableAutoWrap(text)
    contentBox:AddChildToVerticalBox(text)
end

function M.BuildContent(S)
    if not IsValid(S.contentBox) then
        return
    end
    S.contentDirty = false

    pcall(function()
        S.contentBox:ClearChildren()
    end)
    Session.ClearLive(S)
    -- The old controls are gone, so their tooltip targets go too. The shared tooltip widget is kept.
    Tooltip.Reset(S)
    -- The title and cursor handles point into the content that was just cleared.
    Effects.ResetContent(S)
    -- The section widgets of the open stagger, one list of widgets per section, refilled below.
    S.fx.sections = {}

    -- Must change every rebuild. Reusing FNames after ClearChildren resurrects zombies —
    -- category (more option rows) breaks harder than language; both are the same control.
    S.contentGen = S.contentGen + 1
    local suffix = tostring(S.contentGen)
    local config = S.config
    local contentBox = S.contentBox

    -- A bar header lives in the band Create put across the top of the panel, and its row is replaced on
    -- every content build, so a new title or hint shows without rebuilding the shell.
    local resolved = config.resolved
    local titleRow
    if InBandVariant(M.HeaderVariant(resolved)) and IsValid(S.headerBand) then
        titleRow = Construct("/Script/UMG.HorizontalBox", S.headerBand, "ModMenu_TitleRow_" .. suffix)
        local placed = pcall(function()
            S.headerBand:SetContent(titleRow)
        end)
        if not placed then
            -- The band would leave the row orphaned and the menu without a title or Close, so the header
            -- moves into the content for the rest of this shell; Header then draws it as a plain header.
            Log("header band refused its row; drawing the header in the content instead")
            S.headerBand = nil
            contentBox:AddChildToVerticalBox(titleRow)
        end
    else
        titleRow = Construct("/Script/UMG.HorizontalBox", contentBox, "ModMenu_TitleRow_" .. suffix)
        contentBox:AddChildToVerticalBox(titleRow)
    end
    M.Header(S, titleRow, resolved, suffix)

    -- Shell chrome: four-side dock picker (no panel rebuild).
    Dock.BuildChrome(S, contentBox, suffix)

    Tabs.BuildStrip(S, contentBox, suffix)
    -- An XP strip has a pane under it with its own outline; the content goes inside it. Any other
    -- variant gets contentBox back unchanged.
    contentBox = Tabs.BuildPane(S, contentBox, suffix)

    AddSpacer(contentBox, "ModMenu_HeadPad_" .. suffix, config.spacing.headPad)

    if #S.sections == 0 then
        local empty = Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_Empty_" .. suffix)
        StyleText(empty, config.fontHint)
        SetLabelText(empty, "No mods registered yet.")
        contentBox:AddChildToVerticalBox(empty)
        return
    end

    local visible = {}
    for _, section in ipairs(S.sections) do
        if Tabs.SectionVisible(S, section) then
            table.insert(visible, section)
        end
    end

    if #visible == 0 then
        local emptyTab = Construct("/Script/UMG.TextBlock", contentBox, "ModMenu_EmptyTab_" .. suffix)
        StyleText(emptyTab, config.fontHint)
        SetLabelText(emptyTab, "No sections on this tab.")
        contentBox:AddChildToVerticalBox(emptyTab)
        return
    end

    -- A section is several widgets added straight to the content box, with no widget of its own, so the
    -- stagger records the children the section added. It is read only when the open motion is on.
    local staggerOn = resolved.motion ~= nil and resolved.motion.open == true
    for sIndex, section in ipairs(visible) do
        local firstChild = staggerOn and Motion.ChildCount(contentBox) or nil
        local collapsed = Collapse.IsCollapsed(S, section)
        local itemParent = contentBox
        if Collapse.IsCollapsible(section) then
            local header = Collapse.BuildHeader(S, section, contentBox, suffix)
            AddDescription(S, section, contentBox, suffix)
            local body = Construct(
                "/Script/UMG.VerticalBox",
                contentBox,
                string.format("ModMenu_SecBody_%s_%s", section.id, suffix)
            )
            contentBox:AddChildToVerticalBox(body)
            Collapse.AttachBody(header, body, collapsed)
            itemParent = body
        else
            -- The title follows the theme's section variant; the stock variant is the plain TextBlock.
            Collapse.BuildTitle(S, section, contentBox, suffix)
            AddDescription(S, section, contentBox, suffix)
        end
        AddSpacer(itemParent, string.format("ModMenu_SecPad_%s_%s", section.id, suffix), config.spacing.gapItem)

        -- Always build children. Collapsed sections hide the body (dropdown-style)
        -- so toggling does not rebuild and flicker under a still-down click.
        local ctx = S.makeWidgetCtx()
        ctx.contentBox = itemParent

        for i, item in ipairs(section.items) do
            local namePrefix = string.format("ModMenu_%s_%s_%d_%s", section.id, tostring(item.id or item.type), i, suffix)
            local widget = Widgets.get(item.type)
            if not widget or not widget.build then
                error("BuildContent: no builder for type " .. tostring(item.type))
            end
            ctx.section = section
            ctx.item = item
            ctx.namePrefix = namePrefix
            local firstNew = #S.liveControls + 1
            widget.build(ctx)
            -- A disabled or hidden item, or one inside a disabled or hidden row or fold, is dimmed or collapsed now.
            ItemState.ApplyItems(S, { item }, true)
            -- Every control this build added is attached, which includes the children of a row or fold.
            for c = firstNew, #S.liveControls do
                Tooltip.Attach(S, S.liveControls[c])
            end
        end

        if staggerOn then
            S.fx.sections[#S.fx.sections + 1] = Motion.ChildrenSince(contentBox, firstChild)
        end

        if sIndex < #visible then
            AddSpacer(contentBox, "ModMenu_Between_" .. section.id .. "_" .. suffix, config.spacing.gapSection)
        end
    end

    -- In touch mode the last buttons of a long section sat on the clip edge of a 1080p screen, so the footer is taller there.
    -- A mouse does not need the extra space, because its clicks on those buttons were already landing.
    local foot = config.spacing.footerPad
    if config.pointerMode == "touch" then
        foot = config.spacing.footerPadTouch
    end
    AddSpacer(contentBox, "ModMenu_Foot_" .. suffix, foot)
end

function M.Teardown(S)
    Confirm.Hide(S, "close")
    Cursor.Destroy(S)
    if IsValid(S.menuRoot) then
        pcall(function()
            S.menuRoot:RemoveFromParent()
        end)
        pcall(function()
            S.menuRoot:RemoveFromViewport()
        end)
    end
    S.menuRoot = nil
    S.contentBox = nil
    S.menuScroll = nil
    S.menuCanvas = nil
    S.panelSlot = nil
    S.panelBorder = nil
    S.panelOutline = nil
    S.headerBand = nil
    S.panelRoot = nil
    Effects.Reset(S)
    S.confirm = nil
    S.confirmRoot = nil
    S.confirmSlot = nil
    S.confirmControls = nil
    -- The tooltip widget was under the removed canvas, so the next show builds a new one.
    S.tooltip = nil
    Session.ClearLive(S)
    S.menuOpen = false
end

--- ClientRestart always destroys the shell. Do not ApplyGameOnly / hide
--- the cursor unless this instance had actually taken input.
function M.Destroy(S, stopPoll)
    -- The poll tick and the close timer that flush autosave stop with the shell, so a pending write is made now.
    Persist.Flush(true)
    if stopPoll then
        stopPoll()
    end
    local wasHoldingInput = S.menuOpen or Instance.IsOpenCountHeld()
    local remaining = Instance.NoteClosed()
    M.Teardown(S)
    if wasHoldingInput then
        InputMode.SetActive(false, remaining)
    end
end

function M.Create(S)
    local config = S.config
    -- The build log line reports this build's widgets and time, so the count and the clock start here.
    Paint.ResetCount()
    local started = os.clock()
    Instance.Ensure(config)
    Instance.BumpCreateAttempts()
    local suffix = Instance.ShellNameSuffix(config)

    local outer = UEHelpers.GetGameInstance()
    if not IsValid(outer) then
        outer = UEHelpers.GetPlayerController()
    end
    if not IsValid(outer) then
        error("No GameInstance or PlayerController to parent the widget")
    end

    -- Names must be unique under GameInstance across ALL mods (ModRef-backed tag/serial).
    -- Each root field is assigned as soon as its object exists, so that when a later call throws,
    -- Ensure's Destroy can still find and tear down everything built so far.
    local hud = Construct("/Script/UMG.UserWidget", outer, "ModMenu_Root_" .. suffix)
    S.menuRoot = hud
    local tree = Construct("/Script/UMG.WidgetTree", hud, "ModMenu_Tree_" .. suffix)
    hud.WidgetTree = tree

    local canvas = Construct("/Script/UMG.CanvasPanel", tree, "ModMenu_Canvas_" .. suffix)
    S.menuCanvas = canvas
    tree.RootWidget = canvas

    local panelRoot, scroll = M.Panel(S, config.resolved, suffix)

    local vbox = Construct("/Script/UMG.VerticalBox", scroll, "ModMenu_VBox_" .. suffix)
    S.contentBox = vbox
    pcall(function()
        scroll:AddChild(vbox)
    end)
    -- After children: constructed ScrollBox often ignores thickness until the slot exists.
    Umg.StyleScrollBox(scroll, config)

    local slot = canvas:AddChildToCanvas(panelRoot)
    S.panelSlot = slot
    if slot then
        Dock.ApplyPercentLayout(slot, config)
    end

    -- The menu starts collapsed; Open shows it. Content is built before the root joins the viewport,
    -- so a build that throws leaves nothing on screen.
    hud:SetVisibility(Session.VIS_COLLAPSED)
    M.BuildContent(S)
    local resolved = config.resolved
    local themeId = (type(resolved) == "table" and resolved.id) or config.theme or "light"
    Log(string.format(
        "built theme=%s items=%d widgets=%d ms=%d",
        tostring(themeId),
        M.CountItems(S.sections),
        Paint.CountWidgets(),
        math.floor((os.clock() - started) * 1000 + 0.5)
    ))

    -- Last call that can throw: the tree is complete before it is added.
    hud:AddToViewport(Instance.GetViewportZ())
    -- Styling again after the viewport add, because the scrollbar thickness can be ignored until then.
    -- Every call inside StyleScrollBox is protected, so it cannot throw.
    Umg.StyleScrollBox(scroll, config)

    local thickPct = (config.widthFrac or 0.32) * 100
    local longPct = (1.0 - (config.topFrac or 0) - (config.bottomFrac or 0)) * 100
    local spanX = thickPct
    local spanY = longPct
    if config.dock == "top" or config.dock == "bottom" then
        spanX = longPct
        spanY = thickPct
    end
    Debug(string.format(
        "Shell ready name=ModMenu_Root_%s z=%d dock=%s (~%.0f%% x ~%.0f%%). Sections: %d",
        suffix,
        Instance.GetViewportZ(),
        tostring(config.dock),
        spanX,
        spanY,
        #S.sections
    ))
end

function M.Ensure(S)
    if IsValid(S.menuRoot) and IsValid(S.contentBox) then
        return true
    end
    local ok, err = pcall(M.Create, S)
    if not ok then
        Log("CreateShell failed: " .. tostring(err))
        M.Destroy(S, S.stopPoll)
        return false
    end
    return IsValid(S.menuRoot)
end

return M
