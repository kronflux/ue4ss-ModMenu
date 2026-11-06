--[[
  ModMenu.core.paint — drawing primitives for themes: brushes, state shapes, text and fonts, blur,
  shadows and a widget count.

  Every style is written field by field into the structs a widget already owns, after construction
  and before the tree is first shown, because Slate copies those structs when it first builds the
  widget and SetStyle can end the process (field notes 28 and 29). Engine globals are touched only
  inside functions, so the module loads under the no-game spec runner, and the pure decisions take
  their engine calls as arguments.
]]

local Util = require("ModMenu.core.util")
local Theme = require("ModMenu.core.theme")
local Umg = require("ModMenu.core.umg")

local M = {}

-- Engine enum values.
local VIS_HIDDEN, VIS_HIT_TEST_INVISIBLE = 2, 3
local DRAW_NONE, DRAW_BOX, DRAW_ROUNDED = 0, 1, 4
local ROUND_FIXED, ROUND_HALF_HEIGHT = 0, 1
local H_FILL, H_CENTER = 0, 2
local V_FILL, V_CENTER = 0, 2

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

-- Font ids every game has, because they ship with the engine. Every chain ends at roboto.
local BUILTIN_FONTS = {
    roboto = "/Engine/EngineFonts/Roboto.Roboto",
    mono = "/Engine/EngineFonts/DroidSansMono.DroidSansMono",
}
local LAST_FONT = "roboto"

-- Font ids the host added through Init's fonts option, id to object path.
local fontPaths = {}

-- Loaded assets by object path; false records a path that did not load, so it is not searched again.
local assetCache = {}

-- Messages already logged, keyed by what they report, so the log names each missing asset, font
-- id or failed write once per session (field note 33).
local logged = {}

-- The Umg construct count at the last ResetCount, so CountWidgets reports one build's widgets.
local countBase = 0

local function Alpha(color, a)
    return { R = color.R, G = color.G, B = color.B, A = a }
end

local function LogOnce(key, msg)
    if not logged[key] then
        logged[key] = true
        Util.Log(msg)
    end
end

--- Run fn guarded, and log its first failure for an area once per session, so a write that fails
--- on every build does not flood the log.
local function TryLogged(area, fn)
    local ok, err = pcall(fn)
    if not ok then
        LogOnce("failed:" .. area, "paint: " .. area .. " failed: " .. tostring(err))
    end
    return ok
end

--- The text size to write for a theme size. An explicit font size from Init (fontTitle, fontItem
--- and the rest) wins over the theme. Otherwise a theme size, which is a desktop size at fontScale
--- 1, is scaled by fontScale and by the touch multiplier as config.lua scales its own sizes.
--- With no theme size the config's size is used.
---@param config table
---@param themeSize number|nil
---@param configKey string such as "fontItem"
---@return number
function M.TextSize(config, themeSize, configKey)
    local overrides = config._fontOverride
    if type(overrides) == "table" and overrides[configKey] then
        return config[configKey]
    end
    if type(themeSize) ~= "number" then
        return config[configKey]
    end
    local m = 1
    if config.pointerMode == "touch" then
        m = config.touchFontScale or 1.75
    end
    local n = math.floor(themeSize * (config.fontScale or 1) * m + 0.5)
    if n < 1 then
        n = 1
    end
    return n
end

--- A margin from a number for every side, or from four numbers in left, top, right, bottom order.
---@param p number|table|nil
---@return table
function M.Margin(p)
    if type(p) == "table" then
        return { Left = p[1] or 0, Top = p[2] or 0, Right = p[3] or 0, Bottom = p[4] or 0 }
    end
    local n = tonumber(p) or 0
    return { Left = n, Top = n, Right = n, Bottom = n }
end

--- The four corner radii of a radius that is a number or a list of four numbers.
local function Radii(radius)
    if type(radius) == "table" then
        return { radius[1] or 0, radius[2] or 0, radius[3] or 0, radius[4] or 0 }
    end
    local r = tonumber(radius) or 0
    return { r, r, r, r }
end

local function LargestRadius(radius)
    local radii = Radii(radius)
    return math.max(radii[1], radii[2], radii[3], radii[4])
end

--- True when a shape has square corners, is not a pill and has no outline, so a plain recoloured
--- Border draws it exactly. Only such a shape may be recoloured with SetBrushColor (field note 30).
---@param spec table|nil
---@return boolean
function M.IsFlat(spec)
    if spec == nil then
        return true
    end
    if spec.pill then
        return false
    end
    if (tonumber(spec.width) or 0) > 0 then
        return false
    end
    return LargestRadius(spec.radius) <= 0
end

--- True when a state button needs its own shape per state, because some state is not flat or an
--- edge is drawn. False keeps the legacy recoloured button, so light and dark keep today's tree.
---@param states table
---@return boolean
function M.NeedsShapes(states)
    if states == nil then
        return false
    end
    for _, key in ipairs({ "normal", "hover", "pressed", "disabled" }) do
        if states[key] ~= nil and not M.IsFlat(states[key]) then
            return true
        end
    end
    local edge = states.edge
    return edge ~= nil and (tonumber(edge.width) or 1) > 0
end

--- The pointer state a button shows: disabled wins, then pressed, then hover.
---@param hovered boolean
---@param pressed boolean
---@param enabled boolean
---@return string
function M.StateFor(hovered, pressed, enabled)
    if enabled == false then
        return "disabled"
    end
    if pressed then
        return "pressed"
    end
    if hovered then
        return "hover"
    end
    return "normal"
end

-- Each state falls back to the state below it when it has no shape of its own.
local SHAPE_FALLBACK = {
    pressed = { "pressed", "hover", "normal" },
    hover = { "hover", "normal" },
    disabled = { "disabled", "normal" },
    normal = { "normal" },
}

--- The key of the shape that draws a state, from the shapes a button has.
---@param shapes table
---@param state string
---@return string
function M.ShapeKey(shapes, state)
    for _, key in ipairs(SHAPE_FALLBACK[state] or SHAPE_FALLBACK.normal) do
        if shapes[key] ~= nil then
            return key
        end
    end
    return "normal"
end

--- Text as a text style shows it. Paint.Text never sets text, so a caller that sets a caption
--- passes it through here to apply the style's upper.
---@param text any
---@param textSpec table|nil
---@return string
function M.Caption(text, textSpec)
    local s = tostring(text or "")
    if textSpec ~= nil and textSpec.upper == true then
        return s:upper()
    end
    return s
end

------------------------------------------------------------------------------------------
-- Widget count
------------------------------------------------------------------------------------------

--- The widgets constructed since the last ResetCount. Paint builds every widget through
--- Umg.Construct, so the count covers paint and every other Umg.Construct call.
---@return integer
function M.CountWidgets()
    return Umg.ConstructCount() - countBase
end

function M.ResetCount()
    countBase = Umg.ConstructCount()
end

------------------------------------------------------------------------------------------
-- Fonts
------------------------------------------------------------------------------------------

local function ClearMisses()
    for path, hit in pairs(assetCache) do
        if hit == false then
            assetCache[path] = nil
        end
    end
end

local function SameFonts(a, b)
    for id, path in pairs(a) do
        if b[id] ~= path then
            return false
        end
    end
    for id in pairs(b) do
        if a[id] == nil then
            return false
        end
    end
    return true
end

--- Set the host's font ids, from config.fonts. When the map changed, the paths that failed are
--- searched again, because a new id or path may now load. An unchanged map, as every Init without
--- fonts gives, keeps the cache, so Init does not repeat LoadAsset for a font known to be missing.
---@param map table|nil
---@return boolean changed
function M.SetFonts(map)
    local next = {}
    if type(map) == "table" then
        for id, path in pairs(map) do
            next[id] = path
        end
    end
    if SameFonts(fontPaths, next) then
        return false
    end
    fontPaths = next
    ClearMisses()
    return true
end

--- Start a new session: every missing asset, font id and failed write is reported again, and a
--- path that failed is searched again. Init does not call this; it is for a host or a test that
--- wants a clean start.
function M.ResetSession()
    logged = {}
    ClearMisses()
end

local function FontPath(id)
    return BUILTIN_FONTS[id] or fontPaths[id]
end

--- The first font of a chain that the finder returns, and the ids that did not load. The chain is
--- an id or a list of ids, and it always ends at roboto. A nil or empty chain picks no font, so the
--- caller leaves the engine's font alone. find(path) returns an asset or nil.
---@param chain string|table|nil
---@param find fun(path: string): any
---@return any asset, string[] missing
function M.PickFont(chain, find)
    local missing = {}
    if type(chain) == "string" then
        chain = { chain }
    end
    if type(chain) ~= "table" or #chain == 0 then
        return nil, missing
    end
    local ids = {}
    for i = 1, #chain do
        ids[#ids + 1] = chain[i]
    end
    if ids[#ids] ~= LAST_FONT then
        ids[#ids + 1] = LAST_FONT
    end
    for _, id in ipairs(ids) do
        local path = FontPath(id)
        local asset = nil
        if path ~= nil then
            asset = find(path)
        end
        if asset ~= nil then
            return asset, missing
        end
        missing[#missing + 1] = id
    end
    return nil, missing
end

--- A loaded asset by object path, loading its package once when it is not in memory yet
--- (field note 13: LoadAsset, then StaticFindObject). Hits and misses are cached. A cached hit is
--- checked again before use, because a level change can collect it and a dead font must not be
--- written into a TextBlock.
---@param path string
---@return any
function M.FindAsset(path)
    local cached = assetCache[path]
    if cached == false then
        return nil
    end
    if cached ~= nil then
        if Util.IsValid(cached) then
            return cached
        end
        assetCache[path] = nil
    end
    local obj = nil
    pcall(function()
        obj = StaticFindObject(path)
    end)
    if not Util.IsValid(obj) and type(LoadAsset) == "function" then
        local package = path:match("^(.-)%.[^/]*$")
        if package ~= nil then
            pcall(LoadAsset, package)
            pcall(function()
                obj = StaticFindObject(path)
            end)
        end
    end
    if Util.IsValid(obj) then
        assetCache[path] = obj
        return obj
    end
    assetCache[path] = false
    LogOnce("asset:" .. path, "asset missing: " .. path)
    return nil
end

--- The UFont for a font id or chain of ids, or nil to keep the engine's font.
---@param fontSpec string|table|nil
---@return any
function M.Font(fontSpec)
    local font, missing = M.PickFont(fontSpec, M.FindAsset)
    -- An id with no path, such as a preset naming kanit when the host gave no path for it, would
    -- otherwise fall to Roboto without a word. A missing path is already logged by FindAsset.
    for _, id in ipairs(missing) do
        if FontPath(id) == nil then
            LogOnce("fontid:" .. tostring(id), "font id " .. tostring(id)
                .. " has no path; add it to Init's fonts option, such as fonts = { "
                .. tostring(id) .. " = \"/Game/Fonts/Name.Name\" }")
        end
    end
    return font
end

------------------------------------------------------------------------------------------
-- Brushes and boxes
------------------------------------------------------------------------------------------

--- Write a shape into an FSlateBrush the widget owns. spec: fill, radius (number or four numbers,
--- top-left first, clockwise), pill, outline, width, and optionally drawAs, size and tiling.
---@param brush any
---@param spec table
function M.Brush(brush, spec)
    local radii = Radii(spec.radius)
    local width = tonumber(spec.width) or 0
    local fill = spec.fill or WHITE
    -- Each area is guarded alone and its first failure is logged once per session, so one failed
    -- write leaves the rest of the brush written and the log names what failed.
    TryLogged("brush tint", function()
        brush.TintColor.SpecifiedColor = fill
        brush.TintColor.ColorUseRule = 0
    end)
    if spec.size ~= nil or spec.tiling ~= nil then
        TryLogged("brush size", function()
            if spec.size ~= nil then
                brush.ImageSize = { X = spec.size[1], Y = spec.size[2] }
            end
            if spec.tiling ~= nil then
                brush.Tiling = spec.tiling
            end
        end)
    end
    TryLogged("brush draw type", function()
        -- An outline needs the rounded box draw type even with square corners, because a plain
        -- box draws no outline.
        brush.DrawAs = spec.drawAs or (M.IsFlat(spec) and DRAW_BOX or DRAW_ROUNDED)
    end)
    TryLogged("brush outline", function()
        local o = brush.OutlineSettings
        o.CornerRadii = { X = radii[1], Y = radii[2], Z = radii[3], W = radii[4] }
        -- With no outline the edge colour is the fill itself, so the antialiased edge has nothing
        -- lighter to fade toward (field note 30).
        o.Color.SpecifiedColor = width > 0 and (spec.outline or fill) or fill
        o.Color.ColorUseRule = 0
        o.Width = width
        o.RoundingType = spec.pill and ROUND_HALF_HEIGHT or ROUND_FIXED
    end)
end

--- A Border drawing a shape, with padding. A flat shape is painted with SetBrushColor on the
--- stock brush, as the library does today, so light and dark keep their exact look and the Border
--- can still be recoloured. Any other shape is written into the Border's own brush.
---@param outer any
---@param name string
---@param spec table
---@param pad number|table|nil
---@return any
function M.Box(outer, name, spec, pad)
    local border = Umg.Construct("/Script/UMG.Border", outer, name)
    if M.IsFlat(spec) then
        pcall(function()
            border:SetBrushColor(spec.fill or WHITE)
        end)
    else
        -- Reading Background can fail on its own, before Brush guards its writes.
        TryLogged("border brush", function()
            M.Brush(border.Background, spec)
        end)
    end
    pcall(function()
        border:SetPadding(M.Margin(pad))
    end)
    return border
end

local function SetShown(widget, on)
    pcall(function()
        widget:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_HIDDEN)
    end)
end

local function AddToOverlay(overlay, widget, pad, halign, valign)
    local slot = overlay:AddChildToOverlay(widget)
    pcall(function()
        slot:SetPadding(M.Margin(pad))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
    return slot
end

------------------------------------------------------------------------------------------
-- Text
------------------------------------------------------------------------------------------

--- Write a text style into a TextBlock. textSpec: font (id or chain), typeface, size, color,
--- spacing, skew, outline, outlineColor, shadow ({ x, y, color } or false). A nil field leaves
--- the engine's value alone, so a theme with no font keeps today's font. typeface "" means the
--- font's default typeface and is not written. sizeOverride, when given, wins over textSpec.size.
--- Paint.Text never sets the text, so upper is applied by the caller through Paint.Caption.
---@param textBlock any
---@param textSpec table
---@param sizeOverride number|nil
function M.Text(textBlock, textSpec, sizeOverride)
    if textBlock == nil or textSpec == nil then
        return
    end
    -- Each font field is its own write into the struct the TextBlock owns, never a whole struct
    -- built from a Lua table, which can crash the game (field note 29). Each write is guarded
    -- alone, so one failed field does not skip the rest.
    local font = textSpec.font ~= nil and M.Font(textSpec.font) or nil
    if font ~= nil then
        pcall(function()
            textBlock.Font.FontObject = font
        end)
    end
    local typeface = textSpec.typeface
    if type(typeface) == "string" and typeface ~= "" then
        pcall(function()
            textBlock.Font.TypefaceFontName = FName(typeface)
        end)
    end
    local size = sizeOverride or textSpec.size
    if size ~= nil then
        pcall(function()
            textBlock.Font.Size = size
        end)
    end
    if textSpec.spacing ~= nil then
        pcall(function()
            textBlock.Font.LetterSpacing = textSpec.spacing
        end)
    end
    if textSpec.skew ~= nil then
        pcall(function()
            textBlock.Font.SkewAmount = textSpec.skew
        end)
    end
    if textSpec.outline ~= nil and textSpec.outline > 0 then
        pcall(function()
            local o = textBlock.Font.OutlineSettings
            o.OutlineSize = textSpec.outline
            o.OutlineColor = textSpec.outlineColor or BLACK
        end)
    end
    if textSpec.color ~= nil then
        pcall(function()
            textBlock:SetColorAndOpacity({ SpecifiedColor = textSpec.color, ColorUseRule = 0 })
        end)
    end
    local shadow = textSpec.shadow
    if type(shadow) == "table" then
        pcall(function()
            textBlock:SetShadowOffset({ X = shadow.x or 0, Y = shadow.y or 0 })
            textBlock:SetShadowColorAndOpacity(shadow.color or Alpha(BLACK, 0.5))
        end)
    end
end

------------------------------------------------------------------------------------------
-- State buttons
------------------------------------------------------------------------------------------

-- A caption with no colour of its own takes the button text colour, as CreateTextButton's labels
-- do. The legacy buttonText is the resolved default role's text (Style.LegacyColors), so it is
-- right for every theme, and a text style's own colour does not turn button captions into body text.
local function LabelColor(style)
    return style.color or Umg.Color("buttonText")
end

local function CreateLabel(outer, name, content, labelStyle)
    local label = Umg.Construct("/Script/UMG.TextBlock", outer, name .. "_BtnLabel")
    local style = labelStyle or {}
    local textSpec = style.textSpec
    Umg.StyleText(label, style.size, LabelColor(style), textSpec)
    Umg.SetLabelText(label, M.Caption(content, textSpec))
    return label
end

local function SetClickMethods(button)
    pcall(function()
        -- Mouse-down and touch-down, so IsPressed is true on pointer-down, as CreateTextButton does.
        if button.SetClickMethod then
            button:SetClickMethod(1)
        end
        if button.SetTouchMethod then
            button:SetTouchMethod(1)
        end
    end)
end

--- The legacy flat button: Border(fill) > Button(transparent) > content, recoloured per state.
local function FlatButton(outer, name, states, content, labelStyle)
    local normal = states.normal.fill
    local derivedHover, derivedPressed = Theme.FillStates(normal)
    local hover = states.hover and states.hover.fill or derivedHover
    local pressed = states.pressed and states.pressed.fill or derivedPressed
    local ctrl
    if type(content) == "string" or content == nil then
        local style = labelStyle or {}
        local caption = M.Caption(content, style.textSpec)
        local fill, button, label = Umg.CreateFilledButton(outer, name, caption, style.color, style.size)
        if style.textSpec ~= nil then
            Umg.StyleText(label, style.size, LabelColor(style), style.textSpec)
        end
        ctrl = { root = fill, widget = button, fill = fill, label = label }
    else
        local fill = Umg.Construct("/Script/UMG.Border", outer, name .. "_Fill")
        local button = Umg.Construct("/Script/UMG.Button", fill, name .. "_Btn")
        SetClickMethods(button)
        pcall(function()
            button:SetContent(content)
            fill:SetPadding(M.Margin(0))
            fill:SetContent(button)
        end)
        ctrl = { root = fill, widget = button, fill = fill }
    end
    ctrl.flat = true
    Umg.SetFillColors(ctrl, normal, hover, pressed)
    ctrl.stateColors.disabled = states.disabled and states.disabled.fill or normal
    return ctrl
end

-- The Button's own brushes draw nothing, so only the shapes inside it show. They are written in
-- place, before first show (field note 29), and the background colour is cleared as well in case
-- a write did not reach the struct.
local function ClearButtonBrushes(button)
    TryLogged("button state brushes", function()
        local style = button.WidgetStyle
        for _, key in ipairs({ "Normal", "Hovered", "Pressed", "Disabled" }) do
            local brush = style[key]
            brush.DrawAs = DRAW_NONE
            brush.TintColor.SpecifiedColor = Alpha(WHITE, 0)
            brush.TintColor.ColorUseRule = 0
        end
        style.NormalPadding = M.Margin(0)
        style.PressedPadding = M.Margin(0)
    end)
    pcall(function()
        button:SetBackgroundColor(Alpha(WHITE, 0))
    end)
end

local function ShapeButton(outer, name, states, content, labelStyle)
    local button = Umg.Construct("/Script/UMG.Button", outer, name .. "_Btn")
    ClearButtonBrushes(button)
    SetClickMethods(button)

    local overlay = Umg.Construct("/Script/UMG.Overlay", button, name .. "_Shapes")
    local normal = states.normal
    -- A missing hover or pressed look is derived from the normal fill and shape, as the flat
    -- button derives its colours, so every button answers the pointer.
    local derivedHover, derivedPressed = Theme.FillStates(normal.fill or WHITE)
    local looks = {
        normal = normal,
        hover = states.hover or { fill = derivedHover, radius = normal.radius, pill = normal.pill,
            outline = normal.outline, width = normal.width },
        pressed = states.pressed or { fill = derivedPressed, radius = normal.radius, pill = normal.pill,
            outline = normal.outline, width = normal.width },
        disabled = states.disabled,
    }
    local shapes = {}
    -- Each look is its own shape in its exact colours, shown and hidden by visibility, because a
    -- rounded or outlined brush recoloured with SetBrushColor shows a rim (field note 30).
    for _, key in ipairs({ "normal", "hover", "pressed", "disabled" }) do
        local look = looks[key]
        if look ~= nil then
            local shape = M.Box(overlay, name .. "_" .. key, look, 0)
            SetShown(shape, key == "normal")
            AddToOverlay(overlay, shape, 0)
            shapes[key] = shape
        end
    end

    -- A Button's state brush did not draw its outline, while a Border did (field note 31), so the
    -- edge is a Border with a clear fill over the shapes.
    local edgeWidget = nil
    local edge = states.edge
    if edge ~= nil and (tonumber(edge.width) or 1) > 0 then
        local edgeColor = edge.outline or WHITE
        edgeWidget = M.Box(overlay, name .. "_edge", {
            fill = Alpha(edgeColor, 0),
            outline = edgeColor,
            width = tonumber(edge.width) or 1,
            radius = edge.radius or normal.radius,
            pill = edge.pill or (edge.pill == nil and normal.pill),
        }, 0)
        SetShown(edgeWidget, true)
        AddToOverlay(overlay, edgeWidget, 0)
    end

    local label = nil
    local style = labelStyle or {}
    if type(content) == "string" or content == nil then
        label = CreateLabel(overlay, name, content, style)
        AddToOverlay(overlay, label, style.pad or { 4, 2, 4, 2 }, H_CENTER, V_CENTER)
    else
        AddToOverlay(overlay, content, style.pad or 0)
    end

    local slot = button:SetContent(overlay)
    pcall(function()
        slot:SetPadding(M.Margin(0))
        slot:SetHorizontalAlignment(H_FILL)
        slot:SetVerticalAlignment(V_FILL)
    end)

    return {
        root = button,
        widget = button,
        shapes = shapes,
        edge = edgeWidget,
        label = label,
        flat = false,
        lastState = "normal",
        shownKey = "normal",
    }
end

--- A button with one look per pointer state. states: normal, hover?, pressed?, disabled? (each a
--- Brush spec) and edge? ({ outline, width, radius?, pill? }). When every state is flat and there
--- is no edge, this is the legacy Border > Button tree recoloured per state, so light and dark keep
--- today's widgets. Otherwise it is Button(clear) > Overlay > one Border per state, the edge Border
--- and the content. content is a caption string, which makes ctrl.label, or a widget.
--- labelStyle (optional): { color, size, textSpec, pad } for the caption and its padding.
--- The caller adds ctrl.root to its parent.
---@param outer any
---@param name string
---@param states table
---@param content string|any
---@param labelStyle table|nil
---@return table ctrl { root, widget, fill?, label?, shapes?, edge?, flat, lastState }
function M.StateButton(outer, name, states, content, labelStyle)
    states = states or {}
    if states.normal == nil then
        states = { normal = { fill = WHITE }, hover = states.hover, pressed = states.pressed,
            disabled = states.disabled, edge = states.edge }
    end
    if M.NeedsShapes(states) then
        return ShapeButton(outer, name, states, content, labelStyle)
    end
    return FlatButton(outer, name, states, content, labelStyle)
end

--- Show a state on a state button. The flat button is recoloured; the shape button shows exactly
--- one shape and hides the one it showed before. Nothing is called when the state has not changed.
---@param ctrl table
---@param state string "normal"|"hover"|"pressed"|"disabled"
function M.ShowState(ctrl, state)
    if ctrl == nil or state == ctrl.lastState then
        return
    end
    ctrl.lastState = state
    if ctrl.flat then
        local colors = ctrl.stateColors
        if ctrl.fill ~= nil and colors ~= nil then
            pcall(function()
                ctrl.fill:SetBrushColor(colors[state] or colors.normal)
            end)
        end
        return
    end
    local shapes = ctrl.shapes
    if shapes == nil then
        return
    end
    local key = M.ShapeKey(shapes, state)
    if key == ctrl.shownKey then
        return
    end
    -- A shape is never recoloured, only shown or hidden (field note 30).
    local before = ctrl.shownKey and shapes[ctrl.shownKey]
    if before ~= nil then
        SetShown(before, false)
    end
    SetShown(shapes[key], true)
    ctrl.shownKey = key
end

--- Enable or disable a state button and show its disabled look.
---@param ctrl table
---@param enabled boolean
function M.SetEnabled(ctrl, enabled)
    ctrl.enabled = enabled ~= false
    pcall(function()
        ctrl.widget:SetIsEnabled(ctrl.enabled)
    end)
    M.ShowState(ctrl, ctrl.enabled and "normal" or "disabled")
end

--- Show the state the pointer puts a state button in, when it changed since the last call. An
--- enabled flat button uses Umg.TrackPointer unchanged.
---@param ctrl table
function M.TrackPointer(ctrl)
    if ctrl == nil or ctrl.widget == nil then
        return
    end
    if ctrl.enabled == false then
        M.ShowState(ctrl, "disabled")
        return
    end
    if ctrl.flat then
        Umg.TrackPointer(ctrl)
        return
    end
    M.ShowState(ctrl, Umg.PointerState(ctrl.widget))
end

------------------------------------------------------------------------------------------
-- Blur and shadows
------------------------------------------------------------------------------------------

--- A BackgroundBlur for a panel, and the inset to place it at inside the panel. The corner radius
--- is half the panel's and the inset is 2 px, the setting that filled a rounded frame exactly
--- (field note 32). Returns nil when the strength is not above 0.
---@param outer any
---@param name string
---@param strength number
---@param panelRadius number|table|nil
---@return any widget, number inset
function M.Blur(outer, name, strength, panelRadius)
    if (tonumber(strength) or 0) <= 0 then
        return nil, 0
    end
    local blur = Umg.Construct("/Script/UMG.BackgroundBlur", outer, name)
    local radii = Radii(panelRadius)
    pcall(function()
        blur:SetBlurStrength(strength)
    end)
    pcall(function()
        blur:SetApplyAlphaToBlur(true)
    end)
    pcall(function()
        blur:SetPadding(M.Margin(0))
    end)
    pcall(function()
        blur:SetCornerRadius({ X = radii[1] * 0.5, Y = radii[2] * 0.5, Z = radii[3] * 0.5, W = radii[4] * 0.5 })
    end)
    return blur, 2
end

--- The depth a shadow adds below and to the right of a panel: the hard shadow's depth, or the
--- last layer's depth, as StyleLab lists layers from shallow to deep, or 0. A layer that is not
--- a list of { alpha, depth } counts as no shadow.
---@param shadowSpec table|nil
---@return number
function M.ShadowDepth(shadowSpec)
    if type(shadowSpec) ~= "table" then
        return 0
    end
    local hard = tonumber(shadowSpec.hardShadow) or 0
    if hard > 0 then
        return hard
    end
    local layers = shadowSpec.shadowLayers
    if type(layers) == "table" and #layers > 0 and type(layers[#layers]) == "table" then
        return math.max(0, tonumber(layers[#layers][2]) or 0)
    end
    return 0
end

--- The shadow layer behind a panel, as StyleLab's panels draw it, and its depth. shadowSpec holds
--- hardShadow and hardShadowColor for a solid offset block, or shadowColor and shadowLayers
--- (a list of { alpha, depth }) for a soft shadow; a hard shadow wins. The returned Overlay fills
--- the same overlay slot as the panel, and the panel takes padding { 0, 0, depth, depth }, so
--- Paint.WithShadow does both. Returns nil, 0 when there is no shadow.
---@param outer any
---@param name string
---@param shadowSpec table|nil
---@param radius number|table|nil
---@return any widget, number depth
function M.Shadow(outer, name, shadowSpec, radius)
    local depth = M.ShadowDepth(shadowSpec)
    if shadowSpec == nil or depth <= 0 then
        return nil, 0
    end
    local layer = Umg.Construct("/Script/UMG.Overlay", outer, name)
    SetShown(layer, true)
    local hard = tonumber(shadowSpec.hardShadow) or 0
    if hard > 0 then
        local block = M.Box(layer, name .. "_hard", { fill = shadowSpec.hardShadowColor or BLACK, radius = radius }, 0)
        AddToOverlay(layer, block, { hard, hard, 0, 0 })
        return layer, depth
    end
    local radii = Radii(radius)
    local shadeRadius = { radii[1] + 2, radii[2] + 2, radii[3] + 2, radii[4] + 2 }
    local color = shadowSpec.shadowColor or BLACK
    for i, entry in ipairs(shadowSpec.shadowLayers or {}) do
        if type(entry) == "table" then
            local a, d = tonumber(entry[1]) or 0, math.max(0, tonumber(entry[2]) or 0)
            local dx = math.floor(d * 0.5 + 0.5)
            local shade = M.Box(layer, name .. "_" .. i, { fill = Alpha(color, a), radius = shadeRadius }, 0)
            -- A layer deeper than the last one would give a negative margin, so each side stops at 0.
            AddToOverlay(layer, shade, { dx, d, math.max(0, depth - dx), math.max(0, depth - d) })
        end
    end
    return layer, depth
end

--- A panel body with its shadow behind it: an Overlay holding the shadow layer and the body, or
--- the body itself when there is no shadow.
---@param outer any
---@param name string
---@param shadowSpec table|nil
---@param radius number|table|nil
---@param body any
---@return any
function M.WithShadow(outer, name, shadowSpec, radius, body)
    if M.ShadowDepth(shadowSpec) <= 0 then
        return body
    end
    local root = Umg.Construct("/Script/UMG.Overlay", outer, name)
    local layer, depth = M.Shadow(root, name .. "_Shadow", shadowSpec, radius)
    AddToOverlay(root, layer, 0)
    AddToOverlay(root, body, { 0, 0, depth, depth })
    return root
end

return M
