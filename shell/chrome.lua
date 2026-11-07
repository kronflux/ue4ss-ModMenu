--[[
  ModMenu.shell.chrome — window frames: the title bars of Windows 11, Windows XP and Windows
  Classic, the macOS traffic lights, their caption buttons and the status bar.

  A minimise or close button closes the menu, and maximise only shows its looks, because a menu has
  no window to minimise or maximise. The red and yellow lights close and the green one does nothing.
  Every cross is drawn by Paint.Cross, so no game texture is used. Each part is built from shapes
  that are shown or hidden, never recoloured, and the pointer looks come from Paint.StateButton
  states, plus a ctrl.onState hook for the few swaps a state cannot express.
]]

local Umg = require("ModMenu.core.umg")
local Paint = require("ModMenu.core.paint")
local Style = require("ModMenu.core.style")

local Construct = Umg.Construct

local M = {}

local H_FILL, H_LEFT, H_CENTER = 0, 1, 2
local V_FILL, V_TOP, V_CENTER, V_BOTTOM = 0, 1, 2, 3

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

-- Header variants this module draws, and the ones among them that sit in a band across the top of
-- the panel. The mac header is a row in the content, so it has no band.
M.VARIANTS = { window = true, mac = true, xpbar = true, classic = true }
M.BAND = { window = true, xpbar = true, classic = true }

local STYLE_OF = { window = "win11", xpbar = "xp", classic = "classic" }

-- The caption buttons of each operating system look, in drawing order, with their size.
local SIZES = { win11 = { 46, 32 }, xp = { 21, 21 }, classic = { 16, 14 } }
local KINDS = { "min", "max", "close" }

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local function Mix(a, b, t)
    return {
        R = a.R + (b.R - a.R) * t,
        G = a.G + (b.G - a.G) * t,
        B = a.B + (b.B - a.B) * t,
        A = (a.A or 1) + ((b.A or 1) - (a.A or 1)) * t,
    }
end

local function Radii(radius)
    if type(radius) == "table" then
        return { radius[1] or 0, radius[2] or 0, radius[3] or 0, radius[4] or 0 }
    end
    local r = tonumber(radius) or 0
    return { r, r, r, r }
end

--- The looks of a Windows Classic caption button: raised, and sunken with the symbol nudged down and
--- right while pressed. A panel without a usable bevel gets one derived from the button face, so the
--- press still shows, because a look with no bevel is flat and never applies its shift.
---@param face table
---@param bevel table|nil
---@return table states { normal, hover, pressed }
function M.ClassicStates(face, bevel)
    if type(bevel) ~= "table" or bevel.light == nil or bevel.dark == nil then
        bevel = { light = Mix(face, WHITE, 0.6), dark = Mix(face, BLACK, 0.55) }
    end
    local normal = { fill = face, bevel = bevel }
    return {
        normal = normal,
        hover = normal,
        pressed = { fill = face, bevel = bevel, sunken = true, shift = { x = 1, y = 1 } },
    }
end

---@param header string
---@return string|nil the control style for a header variant, or nil when it has none
function M.ControlStyle(header)
    return STYLE_OF[header]
end

--- The caption controls of a control style: kind, what a click does and the button size. With
--- captions "close" only the close button is returned.
---@param style string "win11"|"xp"|"classic"
---@param captions string|nil "all" (default) or "close"
---@return table[] { { kind, action, size }, ... }
function M.Controls(style, captions)
    local size = SIZES[style]
    local out = {}
    if size == nil then
        return out
    end
    for _, kind in ipairs(KINDS) do
        if captions ~= "close" or kind == "close" then
            out[#out + 1] = {
                kind = kind,
                action = kind == "max" and "none" or "close",
                size = { size[1], size[2] },
            }
        end
    end
    return out
end

--- The three macOS lights in order close, minimise, maximise: the fill, the colour of the symbol
--- shown while one is hovered, and what a click does.
---@return table[] { { kind, fill, ink, action }, ... }
function M.TrafficLights()
    local defs = {
        { "close", "#FF5F57", "#4D0000", "close" },
        { "min", "#FEBC2E", "#995700", "close" },
        { "max", "#28C840", "#006500", "none" },
    }
    local out = {}
    for i, def in ipairs(defs) do
        out[i] = { kind = def[1], fill = Style.Hex(def[2]), ink = Style.Hex(def[3]), action = def[4] }
    end
    return out
end

--- Every stop of a gradient mixed towards a colour, which is how XP's lit and pressed looks are made.
---@param stops table[]
---@param towards table
---@param amount number
---@return table[]
function M.Shade(stops, towards, amount)
    local out = {}
    for i, c in ipairs(stops) do
        out[i] = Mix(c, towards, amount)
    end
    return out
end

------------------------------------------------------------------------------------------
-- Layout helpers
------------------------------------------------------------------------------------------

local function Sized(outer, name, child, w, h)
    local box = Construct("/Script/UMG.SizeBox", outer, name)
    pcall(function()
        if w ~= nil then
            box:SetWidthOverride(w)
        end
        if h ~= nil then
            box:SetHeightOverride(h)
        end
        box:SetContent(child)
    end)
    return box
end

local function OverlayAdd(overlay, widget, pad, halign, valign)
    pcall(function()
        local slot = overlay:AddChildToOverlay(widget)
        slot:SetPadding(Paint.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
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

local function WithColor(spec, color)
    local out = {}
    for k, v in pairs(spec or {}) do
        out[k] = v
    end
    out.color = color
    return out
end

local function Text(outer, name, text, spec, size)
    local block = Construct("/Script/UMG.TextBlock", outer, name)
    Paint.Text(block, spec, size)
    Umg.SetLabelText(block, Paint.Caption(text, spec))
    return block
end

-- The text style the menu's body text uses, from the resolved style, for the bar title and the status bar.
local function BodySpec(resolved)
    return resolved.body or resolved.hint or {}
end

------------------------------------------------------------------------------------------
-- Caption buttons
------------------------------------------------------------------------------------------

-- The symbol on a caption button: a bar, a square outline or a drawn cross.
local function Glyph(outer, name, kind, color, size, thickness)
    if kind == "min" then
        return Sized(outer, name, Paint.Box(outer, name .. "_Bar", { fill = color }, 0), size, thickness)
    elseif kind == "max" then
        return Sized(outer, name, Paint.Box(outer, name .. "_Box",
            { fill = Alpha(color, 0), outline = color, width = 1 }, 0), size, size)
    end
    -- The cross is drawn from two bars at 45 degrees, so the bar is longer than the width it covers.
    return Paint.Cross(outer, name, color, math.floor(size * 1.3 + 0.5), thickness)
end

local function ShowAll(widgets, on)
    for _, w in ipairs(widgets) do
        Paint.SetShown(w, on)
    end
end

-- The XP caption glyph colour: white unless the header sets captionGlyph.
function M.XpGlyphInk(header)
    return header.captionGlyph or WHITE
end

-- One caption button for a control style. Returns the control and the glyph colour it used.
local function CaptionButton(row, style, def, resolved, suffix)
    local palette = resolved.palette
    local header = resolved.header or {}
    local panel = resolved.panel or {}
    local name = "ModMenu_Cap_" .. def.kind .. "_" .. suffix
    local isClose = def.kind == "close"
    local content = Construct("/Script/UMG.Overlay", row, name .. "_Content")
    local states, onState

    if style == "win11" then
        -- Full-height buttons flush with the top edge. Close turns red with a white cross, and its
        -- hover follows the panel's top-right corner.
        local red = Style.Hex("#C42B1C")
        local hoverFill = isClose and red or Alpha(palette.text, 0.06)
        local pressFill = isClose and Alpha(red, 0.9) or Alpha(palette.text, 0.04)
        local radius = isClose and { 0, Radii(panel.radius)[2], 0, 0 } or 0
        states = {
            normal = { fill = Alpha(hoverFill, 0), radius = radius },
            hover = { fill = hoverFill, radius = radius },
            pressed = { fill = pressFill, radius = radius },
        }
        local glyph = Glyph(content, name .. "_Glyph", def.kind, palette.text, 10, 1)
        OverlayAdd(content, glyph, 0, H_CENTER, V_CENTER)
        Paint.SetShown(glyph, true)
        if isClose then
            local white = Glyph(content, name .. "_White", def.kind, WHITE, 10, 1)
            OverlayAdd(content, white, 0, H_CENTER, V_CENTER)
            Paint.SetShown(white, false)
            onState = function(state)
                local on = state ~= "normal"
                Paint.SetShown(white, on)
                Paint.SetShown(glyph, not on)
            end
        end
    elseif style == "xp" then
        -- Rounded buttons with a glossy gradient: lighter on hover and darker while pressed. Close is red.
        local stops = isClose and header.closeStops or header.controlStops
        if type(stops) ~= "table" or #stops < 2 then
            stops = header.barStops
        end
        local function Look(s)
            return { gradient = { stops = s, steps = 10, radius = 3 } }
        end
        states = {
            normal = Look(stops),
            hover = Look(M.Shade(stops, WHITE, 0.25)),
            pressed = Look(M.Shade(stops, BLACK, 0.2)),
        }
        -- The bubble, a soft highlight in the top-left, under the white outline.
        local shine = Sized(content, name .. "_ShineSize",
            Paint.Box(content, name .. "_Shine", { fill = Alpha(WHITE, 0.42), radius = 1, pill = true }, 0), 11, 5)
        OverlayAdd(content, shine, { 3, 2, 0, 0 }, H_LEFT, V_TOP)
        Paint.SetShown(shine, true)
        local ring = Paint.Box(content, name .. "_Ring", { fill = Alpha(WHITE, 0), outline = WHITE, width = 1, radius = 3 }, 0)
        OverlayAdd(content, ring, 0)
        Paint.SetShown(ring, true)
        local ink = M.XpGlyphInk(header)
        local glyph
        if def.kind == "min" then
            glyph = Sized(content, name .. "_GlyphSize", Paint.Box(content, name .. "_Glyph", { fill = ink }, 0), 7, 3)
            OverlayAdd(content, glyph, { 5, 0, 0, 5 }, H_LEFT, V_BOTTOM)
        elseif def.kind == "max" then
            -- A box with a heavy top edge.
            local box = Construct("/Script/UMG.Overlay", content, name .. "_Max")
            OverlayAdd(box, Sized(box, name .. "_MaxBoxSize", Paint.Box(box, name .. "_MaxBox",
                { fill = Alpha(ink, 0), outline = ink, width = 1 }, 0), 10, 10))
            OverlayAdd(box, Sized(box, name .. "_MaxTopSize", Paint.Box(box, name .. "_MaxTop", { fill = ink }, 0), 10, 3),
                0, H_FILL, V_TOP)
            glyph = Sized(content, name .. "_GlyphSize", box, 10, 10)
            OverlayAdd(content, glyph, 0, H_CENTER, V_CENTER)
        else
            glyph = Glyph(content, name .. "_Glyph", "close", ink, 10, 2)
            OverlayAdd(content, glyph, 0, H_CENTER, V_CENTER)
        end
        Paint.SetShown(glyph, true)
    else
        -- Windows Classic: small raised bevel buttons that sink and nudge their symbol while pressed.
        local face = header.controlFace or Style.Hex("#C0C0C0")
        local ink = header.controlGlyph or BLACK
        states = M.ClassicStates(face, panel.bevel)
        local glyph = Glyph(content, name .. "_Glyph", def.kind, ink, isClose and 9 or 7, 2)
        OverlayAdd(content, glyph, 0, H_CENTER, V_CENTER)
        Paint.SetShown(glyph, true)
    end

    local ctrl = Paint.StateButton(row, name, states, content, nil)
    ctrl.kind = "close"
    ctrl.role = "close"
    ctrl.action = def.action
    ctrl.wasPressed = false
    ctrl.onState = onState
    ctrl.notifiedState = "normal"
    return ctrl
end

--- Add the caption buttons of a control style to a row and to the live controls.
---@param S table
---@param row any HorizontalBox
---@param style string
---@param resolved table
---@param suffix string
function M.AddCaptions(S, row, style, resolved, suffix)
    if S.config.showClose == false then
        return
    end
    local defs = M.Controls(style, (resolved.header or {}).captions)
    for index, def in ipairs(defs) do
        local ctrl = CaptionButton(row, style, def, resolved, suffix)
        local gap = 0
        if style == "xp" and index > 1 then
            gap = 2
        elseif style == "classic" and def.kind == "close" then
            gap = 2
        end
        HBoxAdd(row, Sized(row, "ModMenu_CapSize_" .. def.kind .. "_" .. suffix, ctrl.root, def.size[1], def.size[2]),
            false, { gap, 0, 0, 0 }, V_TOP)
        table.insert(S.liveControls, ctrl)
    end
end

--- Add the three macOS lights to a row and to the live controls. One shared table records which
--- light is hovered, and hovering any of them shows the symbol on all three.
---@param S table
---@param row any HorizontalBox
---@param suffix string
function M.AddTrafficLights(S, row, suffix)
    if S.config.showClose == false then
        return
    end
    local glyphs, hovered = {}, {}
    for i, def in ipairs(M.TrafficLights()) do
        local name = "ModMenu_Light_" .. def.kind .. "_" .. suffix
        local content = Construct("/Script/UMG.Overlay", row, name .. "_Content")
        OverlayAdd(content, Paint.Box(content, name .. "_Disc", {
            fill = def.fill, outline = Mix(def.fill, BLACK, 0.15), width = 1, radius = 1, pill = true,
        }, 0))
        local glyph
        if def.kind == "close" then
            glyph = Paint.Cross(content, name .. "_Glyph", def.ink, 10, 1.5)
        elseif def.kind == "min" then
            glyph = Sized(content, name .. "_Glyph", Paint.Box(content, name .. "_Bar", { fill = def.ink }, 0), 6, 1.5)
        else
            glyph = Construct("/Script/UMG.Overlay", content, name .. "_Glyph")
            OverlayAdd(glyph, Sized(glyph, name .. "_H", Paint.Box(glyph, name .. "_HBar", { fill = def.ink }, 0), 6, 1.5),
                0, H_CENTER, V_CENTER)
            OverlayAdd(glyph, Sized(glyph, name .. "_V", Paint.Box(glyph, name .. "_VBar", { fill = def.ink }, 0), 1.5, 6),
                0, H_CENTER, V_CENTER)
        end
        OverlayAdd(content, glyph, 0, H_CENTER, V_CENTER)
        Paint.SetShown(glyph, false)
        glyphs[i] = glyph

        local clear = { fill = Alpha(BLACK, 0), radius = 1, pill = true }
        local ctrl = Paint.StateButton(row, name, {
            normal = clear,
            hover = clear,
            pressed = { fill = Alpha(BLACK, 0.18), radius = 1, pill = true },
        }, content, nil)
        ctrl.kind = "close"
        ctrl.role = "close"
        ctrl.action = def.action
        ctrl.wasPressed = false
        ctrl.notifiedState = "normal"
        ctrl.onState = function(state)
            hovered[i] = state ~= "normal"
            ShowAll(glyphs, hovered[1] == true or hovered[2] == true or hovered[3] == true)
        end
        HBoxAdd(row, Sized(row, name .. "_Size", ctrl.root, 12, 12), false, { i == 1 and 0 or 8, 0, 0, 0 }, V_CENTER)
        table.insert(S.liveControls, ctrl)
    end
end

------------------------------------------------------------------------------------------
-- Title bars
------------------------------------------------------------------------------------------

--- The band across the top of the panel for the window, xpbar and classic headers, or nil when the
--- preset does not give the look what it needs. The band holds a Border in S.headerBand, and each
--- content build puts the title row in it, as the bar header does, so a new title shows without a
--- rebuild and the caption buttons are rebuilt with the other live controls. S.headerBand is set
--- last, so a band that fails part way leaves it nil and the header falls back to plain.
---@param S table
---@param stack any VerticalBox
---@param resolved table
---@param suffix string
---@return any|nil
function M.TopBand(S, stack, resolved, suffix)
    local variant = (resolved.header or {}).variant
    if not M.BAND[variant] then
        return nil
    end
    local header = resolved.header
    if variant == "window" then
        local holder = Paint.Box(stack, "ModMenu_HeaderBand_" .. suffix, { fill = Alpha(WHITE, 0) }, 0)
        local band = Sized(stack, "ModMenu_HeaderBandSize_" .. suffix, holder, nil, 32)
        S.headerBand = holder
        return band
    end
    if type(header.barStops) ~= "table" or #header.barStops < 2 then
        return nil
    end
    -- XP's title bar is a glossy gradient from top to bottom, rounded only at the top; Classic's runs
    -- from left to right and is square.
    local xp = variant == "xpbar"
    local r = Radii(resolved.panel and resolved.panel.radius)[1]
    local stackBox = Construct("/Script/UMG.Overlay", stack, "ModMenu_HeaderBar_" .. suffix)
    local gradient = Paint.Gradient(stackBox, "ModMenu_HeaderGradient_" .. suffix, {
        stops = header.barStops,
        steps = xp and 14 or 24,
        radius = xp and math.max(0, r - 3) or 0,
        horizontal = not xp,
        roundEnds = "first",
    })
    OverlayAdd(stackBox, gradient, 0)
    local holder = Paint.Box(stackBox, "ModMenu_HeaderBand_" .. suffix, { fill = Alpha(WHITE, 0) },
        xp and { 10, 5, 6, 5 } or { 6, 2, 3, 2 })
    OverlayAdd(stackBox, holder, 0, H_FILL, V_CENTER)
    local band = Sized(stack, "ModMenu_HeaderBandSize_" .. suffix, stackBox, nil, xp and 30 or 20)
    S.headerBand = holder
    return band
end

--- The title text colour of the XP and Classic bars: title.color, or white when the style sets none.
---@param resolved table
function M.BandTitleColor(resolved)
    return (resolved.title and resolved.title.color) or WHITE
end

--- The title and the caption buttons of a window, xpbar or classic header, drawn into the row that
--- sits in the band.
---@param S table
---@param row any HorizontalBox
---@param resolved table
---@param suffix string
function M.BandRow(S, row, resolved, suffix)
    local config = S.config
    local variant = resolved.header.variant
    local style = STYLE_OF[variant]
    local title
    if variant == "window" then
        local body = BodySpec(resolved)
        title = Text(row, "ModMenu_Title_" .. suffix, config.title, WithColor(body, resolved.palette.text),
            Paint.TextSize(config, (tonumber(body.size) or 14) - 2, "fontItem"))
        HBoxAdd(row, title, true, { 14, 0, 10, 0 }, V_CENTER)
    else
        -- The style's title colour, white when it sets none. XP lays a dark drop shadow under it, as Windows XP does.
        local spec = WithColor(resolved.title, M.BandTitleColor(resolved))
        spec.shadow = variant == "xpbar" and { x = 1, y = 1, color = resolved.header.titleShadow or Style.Hex("#0F1089") } or false
        title = Text(row, "ModMenu_Title_" .. suffix, config.title, spec,
            Paint.TextSize(config, resolved.title.size, "fontTitle"))
        HBoxAdd(row, title, true, 0, V_CENTER)
    end
    M.AddCaptions(S, row, style, resolved, suffix)
end

--- The macOS header: the traffic lights on the left and the title centred over the whole bar.
---@param S table
---@param row any HorizontalBox
---@param resolved table
---@param suffix string
function M.MacHeader(S, row, resolved, suffix)
    local config = S.config
    local bar = Construct("/Script/UMG.Overlay", row, "ModMenu_MacBar_" .. suffix)
    local lights = Construct("/Script/UMG.HorizontalBox", bar, "ModMenu_Lights_" .. suffix)
    M.AddTrafficLights(S, lights, suffix)
    OverlayAdd(bar, lights, { 2, 0, 0, 0 }, H_LEFT, V_CENTER)
    local title = Text(bar, "ModMenu_Title_" .. suffix, config.title, resolved.title,
        Paint.TextSize(config, resolved.title.size, "fontTitle"))
    OverlayAdd(bar, title, 0, H_CENTER, V_CENTER)
    HBoxAdd(row, Sized(row, "ModMenu_MacBarSize_" .. suffix, bar, nil, 24), true, { 0, 0, 0, 8 }, V_CENTER)
end

--- The status bar along the bottom edge of the panel, as on Windows XP forms: a dividing line and
--- a short status message. Without a fill it uses the panel background, and without a line the
--- palette's line colour.
---@param S table
---@param stack any VerticalBox
---@param resolved table
---@param suffix string
function M.StatusBar(S, stack, resolved, suffix)
    local sb = resolved.panel and resolved.panel.statusBar
    if type(sb) ~= "table" then
        return
    end
    local palette = resolved.palette
    local config = S.config
    -- The bar and the divider join the stack only after both are built, so a failure leaves neither.
    local body = BodySpec(resolved)
    -- The bar follows the panel's bottom corners, and stays flat when they are square.
    local radii = Radii(resolved.panel.radius)
    local bottom = { 0, 0, radii[3], radii[4] }
    local fill = Paint.Box(stack, "ModMenu_StatusBar_" .. suffix, { fill = sb.fill or palette.bg, radius = bottom }, { 8, 3, 8, 4 })
    local text = Text(fill, "ModMenu_StatusText_" .. suffix, sb.text or "Ready", WithColor(body, palette.text),
        Paint.TextSize(config, (tonumber(body.size) or 14) - 2, "fontHint"))
    pcall(function()
        fill:SetContent(text)
    end)
    local line = Paint.Box(stack, "ModMenu_StatusLine_" .. suffix, { fill = sb.line or palette.line }, 0)
    local lineSized = Sized(stack, "ModMenu_StatusLineSize_" .. suffix, line, nil, 1)
    VBoxAdd(stack, lineSized, 0)
    VBoxAdd(stack, fill, 0)
end

return M
