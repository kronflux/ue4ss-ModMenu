--[[
  StyleLab: a gallery of sample menus, each drawn in a different visual style, for choosing what
  ModMenu's themes should look like. It has no game function and does not use the ModMenu library,
  so each styling technique can be tried on its own.

  Pages:
  - F6, F7 and F8 show the favourite styles as full menus: a header, tabs, three sections and an
    action bar. The last one mixes parts of other styles.
  - F9 shows reworked versions of styles that missed, and F10 shows new options.
  - F11 shows popular editor palettes: Dracula, Catppuccin Mocha and Latte, Material, Monokai, Nord.
  - F12 imitates operating systems, light on the top row and dark below: Windows 11, macOS,
    Windows XP and Windows Classic.
  Each key opens its page, switches to it from another page, or closes the gallery when its page
  is already showing. The `stylelab` console command opens and closes the gallery.

  Each card is drawn from a style table with one entry per object type: panel, header, tabs,
  section, button, toggle, slider, progress, choice, field, list, icons and motion. A theme is a set
  of those entries, and a mixed theme takes entries from other themes, so the gallery is also a
  working model of per-object-type styling.

  Each technique counts its successes and failures; the first failure of each is written to
  UE4SS.log and to StyleLab-session.log beside this mod, and a summary follows each page build. A
  step line is written to the session log before each native call, so after a hard crash the last
  step line names the call.

  How styles are written. A style struct built whole in Lua can leave fields uninitialised, which
  crashed DDS2InGameWiki, and Button:SetStyle overflows UE4SS's fixed UFunction parameter buffer.
  So every style is written field by field into the struct the widget already owns, before the
  widget is first shown, because Slate reads those structs when it first builds the widget. Rules
  from earlier runs (framework field notes 30 to 32):
  - No shape is recoloured at run time. SetBrushColor leaves a light rim at a rounded shape's edge,
    so a control with several looks stacks one shape per look, each in its exact colours, and
    shows one at a time.
  - A button's outline is drawn by a Border inside the button, because an outline on the button's
    own state brushes did not draw.
  - A blur's corner radius does not match a frame's radius one to one. Half the frame's radius,
    with the blur inset 2 px, matched in Funnel Runners, and is the default.
]]

local UEHelpers = require("UEHelpers.UEHelpers")

local function ModRoot()
    local src = debug.getinfo(1, "S").source or ""
    src = src:gsub("^@", ""):gsub("\\", "/")
    return src:match("^(.*)/Scripts/") or "."
end

local LOG_PATH = ModRoot() .. "/StyleLab-session.log"
local TRACE = true

local function WriteLine(line)
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(tostring(os.date("%H:%M:%S")), " ", line, "\n")
        f:close()
    end
end

local function Say(msg)
    local line = "[StyleLab] " .. tostring(msg)
    print(line .. "\n")
    WriteLine(line)
end

local function Step(what)
    if TRACE then
        WriteLine("[step] " .. what)
    end
end

local function Valid(obj)
    if obj == nil then
        return false
    end
    local ok, valid = pcall(function()
        return obj:IsValid()
    end)
    return ok and valid == true
end

-- Technique results: name -> { ok = n, failed = n }. Only the first failure per card and technique is logged.
local results = {}
local resultOrder = {}
local failureLogged = {}

local function Try(card, what, fn)
    Step(card .. ": " .. what)
    local ok, err = pcall(fn)
    local r = results[what]
    if r == nil then
        r = { ok = 0, failed = 0 }
        results[what] = r
        resultOrder[#resultOrder + 1] = what
    end
    if ok then
        r.ok = r.ok + 1
    else
        r.failed = r.failed + 1
        local key = card .. ": " .. what
        if not failureLogged[key] then
            failureLogged[key] = true
            Say(key .. " failed: " .. tostring(err))
        end
    end
    return ok
end

------------------------------------------------------------------------------------------
-- Colours. UMG takes linear colours; these helpers take sRGB hex as a designer writes it.
------------------------------------------------------------------------------------------

local function Linear(c)
    c = c / 255
    if c <= 0.04045 then
        return c / 12.92
    end
    return ((c + 0.055) / 1.055) ^ 2.4
end

local function Hex(s, a)
    local r, g, b = s:match("#?(%x%x)(%x%x)(%x%x)")
    return { R = Linear(tonumber(r, 16)), G = Linear(tonumber(g, 16)), B = Linear(tonumber(b, 16)), A = a or 1 }
end

local WHITE = { R = 1, G = 1, B = 1, A = 1 }
local BLACK = { R = 0, G = 0, B = 0, A = 1 }

local function Alpha(c, a)
    return { R = c.R, G = c.G, B = c.B, A = a }
end

local function Mix(a, b, t)
    return {
        R = a.R + (b.R - a.R) * t,
        G = a.G + (b.G - a.G) * t,
        B = a.B + (b.B - a.B) * t,
        A = a.A + (b.A - a.A) * t,
    }
end

local function Margin(p)
    if type(p) == "number" then
        return { Left = p, Top = p, Right = p, Bottom = p }
    end
    return { Left = p[1] or 0, Top = p[2] or 0, Right = p[3] or 0, Bottom = p[4] or 0 }
end

local function Merge(base, over)
    local out = {}
    for k, v in pairs(base or {}) do
        out[k] = v
    end
    for k, v in pairs(over or {}) do
        out[k] = v
    end
    return out
end

-- Engine enum values used below.
local H_FILL, H_LEFT, H_CENTER, H_RIGHT = 0, 1, 2, 3
local V_FILL, V_TOP, V_CENTER, V_BOTTOM = 0, 1, 2, 3
local VIS_VISIBLE, VIS_COLLAPSED, VIS_HIDDEN, VIS_HIT_TEST_INVISIBLE = 0, 1, 2, 3
local DRAW_NONE, DRAW_BOX, DRAW_ROUNDED = 0, 1, 4
local TILE_BOTH = 3
local ROUND_FIXED, ROUND_HALF_HEIGHT = 0, 1
local CLIP_TO_BOUNDS = 1

------------------------------------------------------------------------------------------
-- Game and engine assets, from UE4SS_ObjectDump.txt for Funnel Runners. The dump lists what was
-- loaded when it was taken, so every font is looked up at run time with a fallback chain.
------------------------------------------------------------------------------------------

local FONT_DIR = "/Game/StormEscape/UI/Foundation/Fonts/"
local FONT_PATHS = {
    roboto = "/Engine/EngineFonts/Roboto.Roboto",
    kanit = FONT_DIR .. "Kanit/Kanit.Kanit",
    vcr = FONT_DIR .. "vcr_osd_mono.vcr_osd_mono",
    inconsolata = FONT_DIR .. "Inconsolata.Inconsolata",
    lekton = FONT_DIR .. "Lekton.Lekton",
    dsegModern = FONT_DIR .. "DSEG7/DSEG7Modern.DSEG7Modern",
}

local ICON_DIR = "/Game/StormEscape/UI/Foundation/Icons/Texture/"
local TEXTURE_PATHS = {
    check = ICON_DIR .. "T_ui_check-fill.T_ui_check-fill",
    close = ICON_DIR .. "T_ui_close-fill.T_ui_close-fill",
    crown = ICON_DIR .. "T-Icon-vip-crown-fill.T-Icon-vip-crown-fill",
    user = ICON_DIR .. "user-fill.user-fill",
    fuel = ICON_DIR .. "T_UI_fuel.T_UI_fuel",
    bolt = ICON_DIR .. "T_UI_Bolt_Full.T_UI_Bolt_Full",
    emotion = ICON_DIR .. "T-Icon-emotion-fill.T-Icon-emotion-fill",
    map = ICON_DIR .. "T-Map.T-Map",
    arrow = ICON_DIR .. "T-Icon-arrow-left-s-fill.T-Icon-arrow-left-s-fill",
    scanline = "/Game/StormEscape/UI/Foundation/Material/Textures/T_UI_scanline_new_2.T_UI_scanline_new_2",
}

local assetCache = {}

--- A loaded asset by object path, loading its package once when it is not in memory yet.
local function FindAsset(path)
    local cached = assetCache[path]
    if cached ~= nil then
        return cached or nil
    end
    local obj = nil
    pcall(function()
        obj = StaticFindObject(path)
    end)
    if not Valid(obj) and type(LoadAsset) == "function" then
        local package = path:match("^(.-)%.[^/]*$")
        Step("LoadAsset " .. tostring(package))
        pcall(LoadAsset, package)
        pcall(function()
            obj = StaticFindObject(path)
        end)
    end
    if Valid(obj) then
        assetCache[path] = obj
        return obj
    end
    assetCache[path] = false
    Say("asset missing: " .. path)
    return nil
end

--- The first font of a name or list of names that loads, or nil for the engine default.
local function PickFont(names)
    if type(names) == "string" then
        names = { names }
    end
    for _, name in ipairs(names or {}) do
        local path = FONT_PATHS[name]
        local font = path and FindAsset(path) or nil
        if font ~= nil then
            return font
        end
    end
    return nil
end

local function Texture(name)
    return FindAsset(TEXTURE_PATHS[name])
end

--- The typeface names a font defines, so the log shows what TypefaceFontName can select.
local function TypefaceNames(font)
    local names = {}
    pcall(function()
        font.CompositeFont.DefaultTypeface.Fonts:ForEach(function(_, elem)
            local entry = elem:get()
            names[#names + 1] = entry.Name:ToString()
        end)
    end)
    if #names == 0 then
        return "unreadable"
    end
    return table.concat(names, ",")
end

------------------------------------------------------------------------------------------
-- Construction
------------------------------------------------------------------------------------------

local S = {
    root = nil,
    tree = nil,
    canvas = nil,
    pages = {},
    page = nil,
    open = false,
    openedAt = 0,
    clickLatch = false,
    globalClickables = {},
    buildTarget = nil, ---@type table|nil the page whose clickables are being collected
    bannerLabels = {},
    savedInput = nil,
    tickError = false,
}

local classCache = {}
local serial = 0

local function New(kind)
    local cls = classCache[kind]
    if cls == nil then
        cls = StaticFindObject("/Script/UMG." .. kind)
        if not Valid(cls) then
            error("class not found: /Script/UMG." .. kind)
        end
        classCache[kind] = cls
    end
    serial = serial + 1
    Step("construct " .. kind)
    local obj = StaticConstructObject(cls, S.tree, FName("StyleLab_" .. kind .. "_" .. serial))
    if not Valid(obj) then
        error("construct failed: " .. kind)
    end
    return obj
end

--- Write a brush spec into an FSlateBrush the widget owns.
--- spec: fill, radius (number or {tl, tr, br, bl}), pill, outline, width, drawAs, size, tiling
local function PaintBrush(b, spec)
    local radius = spec.radius or 0
    local radii = type(radius) == "table" and radius or { radius, radius, radius, radius }
    local width = spec.width or 0
    local rounded = spec.pill or type(radius) == "table" or radius > 0 or width > 0
    local fill = spec.fill or WHITE
    b.TintColor.SpecifiedColor = fill
    b.TintColor.ColorUseRule = 0
    if spec.size ~= nil then
        b.ImageSize = { X = spec.size[1], Y = spec.size[2] }
    end
    if spec.tiling ~= nil then
        b.Tiling = spec.tiling
    end
    b.DrawAs = spec.drawAs or (rounded and DRAW_ROUNDED or DRAW_BOX)
    local o = b.OutlineSettings
    o.CornerRadii = { X = radii[1], Y = radii[2], Z = radii[3], W = radii[4] }
    -- With no outline, the edge colour is the fill itself, so the antialiased edge has nothing
    -- lighter to fade toward.
    o.Color.SpecifiedColor = width > 0 and (spec.outline or fill) or fill
    o.Color.ColorUseRule = 0
    o.Width = width
    o.RoundingType = spec.pill and ROUND_HALF_HEIGHT or ROUND_FIXED
end

--- A TextBlock. spec: font (name or list), typeface, size, color, spacing, skew, outline,
--- outlineColor, shadow, justify, wrap
local function Text(card, str, spec)
    local t = New("TextBlock")
    Try(card, "set text", function()
        t:SetText(FText(str))
    end)
    Try(card, "font fields", function()
        local f = t.Font
        local font = PickFont(spec.font)
        if font ~= nil then
            f.FontObject = font
        end
        if spec.typeface ~= nil then
            f.TypefaceFontName = FName(spec.typeface)
        end
        f.Size = spec.size or 14
        if spec.spacing ~= nil then
            f.LetterSpacing = spec.spacing
        end
        if spec.skew ~= nil then
            f.SkewAmount = spec.skew
        end
    end)
    if spec.outline ~= nil then
        Try(card, "font outline", function()
            local o = t.Font.OutlineSettings
            o.OutlineSize = spec.outline
            o.OutlineColor = spec.outlineColor or BLACK
        end)
    end
    Try(card, "text colour", function()
        t:SetColorAndOpacity({ SpecifiedColor = spec.color or WHITE, ColorUseRule = 0 })
    end)
    if spec.shadow then
        Try(card, "text shadow", function()
            t:SetShadowOffset({ X = spec.shadow.x, Y = spec.shadow.y })
            t:SetShadowColorAndOpacity(spec.shadow.color)
        end)
    end
    if spec.justify ~= nil then
        pcall(function()
            t:SetJustification(spec.justify)
        end)
    end
    if spec.wrap then
        pcall(function()
            t:SetAutoWrapText(true)
        end)
    end
    return t
end

local function SetTextColor(t, color)
    pcall(function()
        t:SetColorAndOpacity({ SpecifiedColor = color, ColorUseRule = 0 })
    end)
end

local function SetLabel(t, str)
    pcall(function()
        t:SetText(FText(str))
    end)
end

--- Show or hide a widget without changing layout or blocking clicks.
local function SetShown(w, on)
    pcall(function()
        w:SetVisibility(on and VIS_HIT_TEST_INVISIBLE or VIS_HIDDEN)
    end)
end

local function Box(card, spec, pad)
    local b = New("Border")
    Try(card, "border brush", function()
        PaintBrush(b.Background, spec)
    end)
    pcall(function()
        b:SetPadding(Margin(pad or 0))
    end)
    return b
end

local function Sized(w, width, height)
    local s = New("SizeBox")
    pcall(function()
        if width ~= nil then
            s:SetWidthOverride(width)
        end
        if height ~= nil then
            s:SetHeightOverride(height)
        end
    end)
    s:SetContent(w)
    return s
end

local function VAdd(box, w, pad, halign)
    local slot = box:AddChildToVerticalBox(w)
    pcall(function()
        slot:SetPadding(Margin(pad or 0))
        slot:SetHorizontalAlignment(halign or H_FILL)
    end)
    return slot
end

local function HAdd(box, w, opts)
    opts = opts or {}
    local slot = box:AddChildToHorizontalBox(w)
    pcall(function()
        if opts.fill then
            slot:SetSize({ SizeRule = 1, Value = opts.fill })
        else
            slot:SetSize({ SizeRule = 0, Value = 0 })
        end
        slot:SetPadding(Margin(opts.pad or 0))
        slot:SetVerticalAlignment(opts.valign or V_CENTER)
        slot:SetHorizontalAlignment(opts.halign or H_FILL)
    end)
    return slot
end

local function OAdd(overlay, w, pad, halign, valign)
    local slot = overlay:AddChildToOverlay(w)
    pcall(function()
        slot:SetPadding(Margin(pad or 0))
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
    end)
    return slot
end

local function SetContentAligned(parent, child, halign, valign, pad)
    local slot = parent:SetContent(child)
    pcall(function()
        slot:SetHorizontalAlignment(halign or H_FILL)
        slot:SetVerticalAlignment(valign or V_FILL)
        slot:SetPadding(Margin(pad or 0))
    end)
    return slot
end

local function AddClickable(card, widget, onClick)
    local list = S.buildTarget and S.buildTarget.clickables or S.globalClickables
    list[#list + 1] = { widget = widget, onClick = onClick, card = card }
end

--- A button whose state brushes come from states.normal, states.hovered and states.pressed. The
--- content fills the button. With no onClick the button is drawn disabled.
local function Button(card, states, content, onClick, pad)
    local b = New("Button")
    Try(card, "button style fields", function()
        local s = b.WidgetStyle
        PaintBrush(s.Normal, states.normal)
        PaintBrush(s.Hovered, states.hovered or states.normal)
        PaintBrush(s.Pressed, states.pressed or states.hovered or states.normal)
        PaintBrush(s.Disabled, states.normal)
        s.NormalPadding = Margin(0)
        s.PressedPadding = Margin(0)
    end)
    if content ~= nil then
        SetContentAligned(b, content, H_FILL, V_FILL, pad or 0)
    end
    if onClick ~= nil then
        AddClickable(card, b, onClick)
    else
        pcall(function()
            b:SetIsEnabled(false)
        end)
    end
    return b
end

--- A transparent button that washes in with a colour on hover and press.
local function WashStates(color, radius, pill)
    return {
        normal = { fill = Alpha(color, 0), radius = radius, pill = pill },
        hovered = { fill = Alpha(color, 0.08), radius = radius, pill = pill },
        pressed = { fill = Alpha(color, 0.16), radius = radius, pill = pill },
    }
end

local function Image(card, texture, size, tint)
    local img = New("Image")
    if texture ~= nil then
        Try(card, "texture brush", function()
            img:SetBrushFromTexture(texture, false)
        end)
    end
    if tint ~= nil then
        pcall(function()
            img:SetColorAndOpacity(tint)
        end)
    end
    return Sized(img, size, size), img
end

------------------------------------------------------------------------------------------
-- Style tables. Each theme names a palette and overrides only the object types it changes.
------------------------------------------------------------------------------------------

--- An object-type entry without its colours, so a mixed theme takes the shape from one theme and
--- the colours from its base. Lists such as a colour ramp are kept.
local function StripColors(entry)
    local out = {}
    for k, v in pairs(entry or {}) do
        if not (type(v) == "table" and v.R ~= nil) then
            out[k] = v
        end
    end
    return out
end

--- Fill in every object type of a theme from its palette, so builders read one complete table.
local function Resolve(t)
    if t.base ~= nil then
        local merged = Merge(t.base, { name = t.name, subtitle = t.subtitle, footer = t.footer, icon = t.icon })
        for objType, source in pairs(t.parts) do
            merged[objType] = StripColors(source[objType])
        end
        return Resolve(merged)
    end
    local p = t.palette
    p.dangerText = p.dangerText or WHITE
    p.secondaryText = p.secondaryText or p.text
    p.track = p.track or Mix(p.bg, p.text, 0.15)
    local s = {
        name = t.name,
        subtitle = t.subtitle,
        footer = t.footer,
        p = p,
        upper = t.upper,
        hoverToward = t.hoverToward or WHITE,
        hoverAmount = t.hoverAmount or 0.14,
        textShadow = t.textShadow,
        icon = t.icon or "user",
    }
    s.title = Merge({ font = "roboto", typeface = "Bold", size = 20, color = p.text }, t.title)
    s.body = Merge({ font = "roboto", typeface = "Regular", size = 14, color = p.text }, t.body)
    s.data = Merge({ font = s.body.font, typeface = "Bold", size = 22, color = p.accent }, t.data)
    s.panel = Merge({ radius = 12, width = 1, outline = p.line, fill = p.bg, header = "badge", pad = 18 }, t.panel)
    s.panel.blurRadius = s.panel.blurRadius or s.panel.radius * 0.5
    s.panel.blurInset = s.panel.blurInset or 2
    s.button = Merge({ variant = "fill", radius = 8, width = 1, height = 36 }, t.button)
    s.toggle = Merge({
        variant = "switch",
        trackOn = p.accent,
        trackOff = Mix(p.bg, p.text, 0.22),
        knobOn = WHITE,
        knobOff = WHITE,
        w = 36,
        h = 20,
        -- Checkbox colours: the box when off and on, its edge, and the check mark.
        checkOff = Alpha(p.text, 0),
        checkOn = p.accent,
        checkEdge = p.text,
        checkEdgeOn = p.accent,
        checkMark = p.accentText,
    }, t.toggle)
    s.slider = Merge({ thumb = "round", thickness = 4, size = 16, track = p.track, thumbFill = WHITE,
        thumbEdge = p.accent, thumbHover = p.accent }, t.slider)
    s.progress = Merge({ variant = "bar", height = 8, radius = 4, segments = 12, gap = 3, track = p.track,
        fill = p.accent }, t.progress)
    s.choice = Merge({ variant = "joined", radius = s.button.radius, pill = s.button.pill, markFill = p.accent,
        markText = p.accentText }, t.choice)
    local tabDefault = ({ joined = "joined", chips = "chips", tabs = "tabs" })[s.choice.variant]
    s.tabs = Merge({ variant = tabDefault, radius = s.choice.radius, pill = s.choice.pill, markFill = s.choice.markFill,
        markText = s.choice.markText, trackFill = s.choice.trackFill, edge = s.choice.edge }, t.tabs)
    s.section = Merge({ variant = "label", color = p.muted }, t.section)
    s.field = Merge({ fill = Mix(p.bg, p.text, 0.07), outline = p.line, radius = s.button.radius, pill = s.button.pill }, t.field)
    s.icons = Merge({ tint = p.accent, alt = p.muted }, t.icons)
    s.motion = t.motion or {}
    return s
end

------------------------------------------------------------------------------------------
-- Favourites
------------------------------------------------------------------------------------------

local SLATE = {
    name = "Slate", subtitle = "Modern dark", icon = "user",
    footer = "Rounded shapes, native hover and pressed states, an offset shadow, Roboto.",
    palette = { bg = Hex("#1C1F26", 0.97), text = Hex("#E7E9EE"), muted = Hex("#8A93A3"), accent = Hex("#4C8DFF"),
        accentText = WHITE, danger = Hex("#E5484D"), surface = Hex("#2A2F39"), line = Hex("#2D323C"),
        track = Hex("#2F3541") },
    panel = { radius = 14, shadow = { color = BLACK, layers = { { 0.30, 3 }, { 0.20, 7 }, { 0.10, 12 } } } },
    toggle = { trackOff = Hex("#3A404C") },
}

local GLASS = {
    name = "Glass", subtitle = "Frosted, over the game", icon = "emotion",
    footer = "A blur under a translucent rounded panel, outline buttons, text shadows, Roboto Light.",
    palette = { bg = Hex("#0F1420", 0.38), text = WHITE, muted = Hex("#C9D3E3"), accent = Hex("#7CC8FF"),
        accentText = Hex("#06121C"), danger = Hex("#FF6B7A"), surface = Hex("#FFFFFF", 0.10),
        line = Hex("#FFFFFF", 0.28), track = Hex("#FFFFFF", 0.18) },
    panel = { radius = 18, blur = 18 },
    button = { variant = "ghost", radius = 10 },
    title = { typeface = "Light", size = 24, spacing = 40 },
    data = { typeface = "Light", size = 26 },
    toggle = { trackOff = Hex("#FFFFFF", 0.22) },
    field = { fill = Hex("#FFFFFF", 0.08) },
    textShadow = { x = 1, y = 1, color = { R = 0, G = 0, B = 0, A = 0.65 } },
    hoverAmount = 0.18,
}

local STORM = {
    name = "Storm", subtitle = "Amber on slate", icon = "bolt",
    footer = "Kanit, a font the game ships, with amber accents on cool slate and small corners.",
    palette = { bg = Hex("#141A22", 0.96), text = Hex("#EDEFF2"), muted = Hex("#9AA6B2"), accent = Hex("#F2B33D"),
        accentText = Hex("#1A1206"), danger = Hex("#D9473F"), surface = Hex("#26303C"), line = Hex("#2B3542"),
        track = Hex("#26303C") },
    panel = { radius = 4 },
    button = { radius = 2 },
    title = { font = "kanit", typeface = "Bold", size = 22, spacing = 60 },
    body = { font = "kanit", typeface = "Default", size = 14 },
    data = { font = "kanit", typeface = "Bold", size = 24 },
    toggle = { trackOff = Hex("#323D4A") },
    progress = { radius = 2 },
}

local NEON = {
    name = "Neon", subtitle = "Synthwave", icon = "bolt",
    footer = "Pill outline buttons, a 2 px panel outline, a glowing title outline and a slow pulse.",
    palette = { bg = Hex("#0A0612", 0.96), text = WHITE, muted = Hex("#B39DDB"), accent = Hex("#22F1FF"),
        accentText = Hex("#05141A"), danger = Hex("#FF2B6E"), surface = Hex("#22F1FF", 0), line = Hex("#FF2BD6"),
        track = Hex("#2A1A3D") },
    panel = { radius = 20, width = 2 },
    button = { variant = "ghost", pill = true, radius = 1, width = 2 },
    title = { font = "kanit", typeface = "Bold", size = 24, spacing = 80, outline = 2, outlineColor = Hex("#FF2BD6") },
    data = { font = "kanit", typeface = "Bold", size = 26 },
    toggle = { trackOff = Hex("#3A2752") },
    section = { color = Hex("#FF2BD6") },
    motion = { pulse = true },
    hoverAmount = 0.2,
}

local DOPPLER = {
    name = "Doppler", subtitle = "Radar scope", icon = "map",
    footer = "Reflectivity colours, green to magenta, fill the intensity bar. Readings in Inconsolata.",
    palette = { bg = Hex("#07131F", 0.96), text = Hex("#D8E6F0"), muted = Hex("#6F8BA0"), accent = Hex("#35D0BA"),
        accentText = Hex("#04201C"), danger = Hex("#E5332A"), surface = Hex("#10243A"), line = Hex("#1B3550"),
        track = Hex("#10243A") },
    panel = { radius = 8 },
    button = { variant = "soft", radius = 6 },
    title = { typeface = "Light", size = 23, spacing = 30 },
    data = { font = "inconsolata", typeface = "Inconsolata SemiBold", size = 24 },
    progress = { variant = "segments", segments = 16, height = 10, radius = 1,
        ramp = { Hex("#2FB34A"), Hex("#2FB34A"), Hex("#F2D23C"), Hex("#F28C28"), Hex("#E5332A"), Hex("#C83CC8") } },
    choice = { variant = "tabs" },
    section = { variant = "rule" },
}

local WARNING = {
    name = "TORNADO WARNING", subtitle = "Take shelter now", icon = "close",
    footer = "A warning bulletin: a full-width red header, square edges and checkboxes.",
    palette = { bg = Hex("#F4F6F8"), text = Hex("#101418"), muted = Hex("#5B6570"), accent = Hex("#C8102E"),
        accentText = WHITE, danger = Hex("#C8102E"), surface = Hex("#E3E7EB"), line = Hex("#C9D0D6"),
        track = Hex("#D5DBE0") },
    panel = { radius = 0, header = "bar" },
    button = { radius = 0 },
    title = { font = "kanit", typeface = "Bold", size = 22, spacing = 40 },
    toggle = { variant = "check" },
    progress = { radius = 0, height = 10 },
    choice = { radius = 0 },
    section = { variant = "rule", color = Hex("#101418") },
    field = { fill = WHITE },
    hoverToward = BLACK, hoverAmount = 0.1,
}

local NIGHT = {
    name = "Night Drive", subtitle = "Instrument cluster", icon = "fuel",
    footer = "A dashboard at night: an amber segmented gauge and a seven-segment readout.",
    palette = { bg = Hex("#0A0D10", 0.97), text = Hex("#F0E6D8"), muted = Hex("#7A6F62"), accent = Hex("#FF9F1C"),
        accentText = Hex("#1A0F00"), danger = Hex("#FF4A3D"), surface = Hex("#161B20"), line = Hex("#222A31"),
        track = Hex("#161B20") },
    panel = { radius = 16 },
    button = { variant = "soft", radius = 10 },
    title = { typeface = "Bold Italic", size = 21 },
    data = { font = { "dsegModern", "vcr" }, typeface = nil, size = 28 },
    slider = { thumb = "bar", thickness = 3 },
    progress = { variant = "segments", segments = 24, gap = 2, height = 12, radius = 1 },
    choice = { variant = "tabs" },
}

local LOADOUT = {
    name = "Loadout", subtitle = "Shooter HUD", icon = "user", upper = true,
    footer = "Corner brackets, thin cyan lines and a blurred dark glass, as in a loadout screen.",
    palette = { bg = Hex("#0C1218", 0.70), text = Hex("#E8F6FF"), muted = Hex("#7FA3B8"), accent = Hex("#00B4FF"),
        accentText = Hex("#001A26"), danger = Hex("#FF3B4E"), surface = Hex("#00B4FF", 0.08),
        line = Hex("#00B4FF", 0.35), track = Hex("#13202B") },
    panel = { radius = 0, blur = 10, corners = true },
    button = { variant = "ghost", radius = 0 },
    title = { font = "kanit", typeface = "Semibold", size = 22, spacing = 120 },
    body = { font = "kanit", typeface = "Default", spacing = 40 },
    data = { font = "kanit", typeface = "Semibold", size = 26 },
    toggle = { variant = "square" },
    slider = { thumb = "bar" },
    progress = { variant = "segments", segments = 20, gap = 2, height = 8, radius = 0 },
    choice = { radius = 0 },
    section = { color = Hex("#00B4FF") },
}

local COZY = {
    name = "Cozy", subtitle = "Farm life", icon = "emotion",
    footer = "Lavender, mint and peach, every shape a pill, with a soft lilac shadow.",
    palette = { bg = Hex("#EDE7FF"), text = Hex("#3B2F5C"), muted = Hex("#7D71A3"), accent = Hex("#7ED9B5"),
        accentText = Hex("#1F3B30"), danger = Hex("#FF8C7A"), dangerText = Hex("#3B1F1A"), surface = WHITE,
        line = Hex("#D9CEFF"), track = Hex("#DCD3FA") },
    panel = { radius = 28, width = 0, shadow = { color = Hex("#7D5FD8"), layers = { { 0.30, 4 }, { 0.18, 9 }, { 0.08, 15 } } } },
    button = { pill = true, radius = 1, height = 38 },
    title = { font = "kanit", typeface = "Bold", size = 26 },
    body = { font = "kanit", typeface = "Default" },
    data = { font = "kanit", typeface = "Bold", size = 28, color = Hex("#3B2F5C") },
    toggle = { w = 44, h = 24, trackOff = Hex("#D3C8F5") },
    slider = { size = 20, thickness = 8, thumbEdge = Hex("#7ED9B5") },
    progress = { height = 12, radius = 6, fill = Hex("#FFB4A2") },
    choice = { variant = "chips", pill = true, radius = 1 },
    field = { fill = WHITE },
    hoverToward = BLACK, hoverAmount = 0.06,
}

local CARBON = {
    name = "Carbon", subtitle = "Sim racing", icon = "fuel",
    footer = "Italic type for speed, a red strip along the top and thin red indicators.",
    palette = { bg = Hex("#16181B", 0.97), text = Hex("#F4F4F4"), muted = Hex("#8C9096"), accent = Hex("#E10B1F"),
        accentText = WHITE, danger = Hex("#E10B1F"), surface = Hex("#22262A"), line = Hex("#2C3035"),
        track = Hex("#22262A") },
    panel = { radius = 2, strip = 4 },
    button = { radius = 2, roles = { primary = "fill", secondary = "fill", danger = "underline" } },
    title = { typeface = "Bold Italic", size = 24, skew = 0.1 },
    body = { typeface = "Italic" },
    data = { typeface = "Bold Italic", size = 26 },
    slider = { thumb = "bar", thickness = 3 },
    progress = { height = 4, radius = 0 },
    choice = { variant = "tabs" },
}

local BLUEPRINT = {
    name = "Blueprint", subtitle = "Engineering drawing", icon = "map",
    footer = "White linework on blueprint blue. Nothing is filled until it is active.",
    palette = { bg = Hex("#1D4E89", 0.97), text = WHITE, muted = Hex("#BFD3EA"), accent = WHITE,
        accentText = Hex("#1D4E89"), danger = Hex("#FFB3B3"), surface = Hex("#FFFFFF", 0), line = Hex("#FFFFFF", 0.6),
        track = Hex("#FFFFFF", 0.25) },
    panel = { radius = 0 },
    button = { variant = "ghost", radius = 0 },
    title = { font = { "lekton", "inconsolata" }, typeface = nil, size = 22, spacing = 60 },
    body = { font = "inconsolata", typeface = "Inconsolata Regular" },
    data = { font = "inconsolata", typeface = "Inconsolata SemiBold", size = 24, color = WHITE },
    toggle = { variant = "check" },
    slider = { thumb = "square", thumbFill = Hex("#1D4E89"), thumbEdge = WHITE, thumbHover = WHITE },
    progress = { height = 6, radius = 0 },
    choice = { variant = "joined", radius = 0 },
    section = { variant = "rule", color = WHITE },
    field = { fill = Hex("#FFFFFF", 0.06), outline = Hex("#FFFFFF", 0.6) },
    icons = { tint = WHITE, alt = Hex("#BFD3EA") },
}

local MIXED = {
    name = "Mixed", subtitle = "Slate, with parts of four other styles", icon = "crown",
    footer = "Slate's panel and colours, Glass's title, Neon's buttons, Cozy's toggles and choices, Doppler's bar.",
    base = SLATE,
    parts = { title = GLASS, button = NEON, toggle = COZY, choice = COZY, progress = DOPPLER },
}

------------------------------------------------------------------------------------------
-- Reworked styles
------------------------------------------------------------------------------------------

local TERMINAL = {
    name = "Terminal", subtitle = "Phosphor console", icon = "map",
    footer = "An inverted header with a blinking cursor, a soft phosphor glow and a block gauge.",
    palette = { bg = Hex("#07100A", 0.95), text = Hex("#A8FFBF"), muted = Hex("#4FA866"), accent = Hex("#5CFF85"),
        accentText = Hex("#07100A"), danger = Hex("#FF6B5C"), dangerText = Hex("#07100A"),
        surface = Hex("#5CFF85", 0), line = Hex("#5CFF85", 0.45), track = Hex("#143A20") },
    panel = { radius = 2, header = "bar", scanlines = 0.38 },
    button = { variant = "soft", radius = 0 },
    title = { font = "vcr", typeface = nil, size = 20, spacing = 60 },
    body = { font = { "vcr", "inconsolata" }, typeface = nil, size = 14 },
    data = { font = "vcr", typeface = nil, size = 22 },
    toggle = { variant = "text", radius = 0 },
    slider = { thumb = "square", size = 12, thickness = 2, thumbFill = Hex("#5CFF85"), thumbEdge = Hex("#5CFF85") },
    progress = { variant = "segments", segments = 20, gap = 2, height = 8, radius = 0 },
    choice = { variant = "tabs" },
    textShadow = { x = 0, y = 0, color = Hex("#5CFF85", 0.45) },
    motion = { cursor = true },
    hoverAmount = 0.2,
}

local PAPER_BLUE = {
    name = "Paper", subtitle = "Cool blue", icon = "crown",
    footer = "The light Paper layout in cool white and ink blue, with a navy offset shadow.",
    palette = { bg = Hex("#F4F6FA"), text = Hex("#1F2733"), muted = Hex("#5D6878"), accent = Hex("#2F5BEA"),
        accentText = WHITE, danger = Hex("#C0392B"), surface = Hex("#E4E9F2"), line = Hex("#D3DAE6"),
        track = Hex("#DCE2EC") },
    panel = { radius = 6, shadow = { color = Hex("#1E2A44"), layers = { { 0.30, 3 }, { 0.18, 7 }, { 0.08, 12 } } } },
    button = { radius = 4 },
    title = { font = "kanit", typeface = "Semibold", size = 24 },
    data = { font = "kanit", typeface = "Bold", size = 22 },
    toggle = { trackOff = Hex("#CDD5E2") },
    hoverToward = BLACK, hoverAmount = 0.08,
}

local FIELD_KIT = {
    name = "Field Kit", subtitle = "Rescue gear", icon = "fuel",
    footer = "High-visibility yellow on graphite, a thin hazard strip and reflective silver lines.",
    palette = { bg = Hex("#1E2124", 0.97), text = Hex("#F4F5F6"), muted = Hex("#A3A9B0"), accent = Hex("#F5D90A"),
        accentText = Hex("#1E2124"), danger = Hex("#FF5A3C"), surface = Hex("#2B2F33"), line = Hex("#C9CDD2", 0.35),
        track = Hex("#2B2F33") },
    panel = { radius = 6, header = "tape", tape = 6 },
    button = { radius = 4 },
    title = { font = "kanit", typeface = "Semibold", size = 22, spacing = 20 },
    body = { font = "kanit", typeface = "Default" },
    data = { font = "kanit", typeface = "Semibold", size = 24 },
    toggle = { variant = "square", w = 40, h = 22, knobOn = Hex("#1E2124"), trackOff = Hex("#3A3F45") },
    slider = { thumb = "square", size = 16, thumbFill = Hex("#F5D90A"), thumbEdge = Hex("#1E2124") },
    progress = { variant = "segments", segments = 12, gap = 3, height = 10, radius = 1 },
    choice = { variant = "chips", radius = 4 },
}

local HOLOGRAM = {
    name = "Hologram", subtitle = "Projected light", icon = "user",
    footer = "A projection sweep, fine scanlines, and a glitch that splits the title into colour.",
    palette = { bg = Hex("#031018", 0.55), text = Hex("#BFF7FF"), muted = Hex("#5FC4D6"), accent = Hex("#48E5FF"),
        accentText = Hex("#002A33"), danger = Hex("#FF5C8A"), surface = Hex("#48E5FF", 0.08), line = Hex("#48E5FF", 0.55),
        track = Hex("#48E5FF", 0.15) },
    panel = { radius = 6, blur = 6, scanlines = 0.32, sweep = true },
    button = { variant = "ghost", radius = 6 },
    title = { font = "kanit", typeface = "Semibold", size = 24, spacing = 60, color = Hex("#E0FBFF") },
    data = { font = "kanit", typeface = "Semibold", size = 26 },
    toggle = { trackOff = Hex("#48E5FF", 0.18), knobOn = Hex("#002A33") },
    slider = { thumbFill = Hex("#002A33") },
    progress = { height = 5, radius = 2 },
    textShadow = { x = 0, y = 0, color = Hex("#48E5FF", 0.6) },
    motion = { glitch = true },
}

local INK = {
    name = "Ink", subtitle = "Black and white", icon = "close",
    footer = "No colour at all: a heavy title, pill buttons and white-on-black switches.",
    palette = { bg = Hex("#000000", 0.97), text = WHITE, muted = Hex("#8F8F8F"), accent = WHITE, accentText = BLACK,
        danger = WHITE, dangerText = BLACK, surface = BLACK, line = Hex("#FFFFFF", 0.85), track = Hex("#333333") },
    panel = { radius = 18, width = 2 },
    button = { pill = true, radius = 1, roles = { primary = "fill", secondary = "ghost", danger = "ghost" } },
    title = { font = "kanit", typeface = "Bold", size = 30 },
    body = { font = "kanit", typeface = "Default" },
    data = { font = "kanit", typeface = "Bold", size = 28, color = WHITE },
    toggle = { knobOn = BLACK, trackOff = Hex("#333333"), knobOff = Hex("#9A9A9A") },
    slider = { thumbFill = WHITE, thumbEdge = WHITE, thumbHover = Hex("#BBBBBB") },
    progress = { height = 6, radius = 3, fill = WHITE },
    choice = { variant = "chips", pill = true, radius = 1 },
    icons = { tint = WHITE, alt = Hex("#8F8F8F") },
    hoverToward = BLACK, hoverAmount = 0.2,
}

------------------------------------------------------------------------------------------
-- New options
------------------------------------------------------------------------------------------

local AURORA = {
    name = "Aurora", subtitle = "Night sky", icon = "emotion",
    footer = "Deep night blue, with aurora green to violet across the intensity bar.",
    palette = { bg = Hex("#0B1026", 0.96), text = Hex("#E6ECFF"), muted = Hex("#8A94C2"), accent = Hex("#5EF2C2"),
        accentText = Hex("#06231B"), danger = Hex("#FF6B8B"), surface = Hex("#1A2147"), line = Hex("#26306A"),
        track = Hex("#1A2147") },
    panel = { radius = 16 },
    button = { radius = 10 },
    title = { typeface = "Light", size = 24, spacing = 20 },
    data = { typeface = "Light", size = 28 },
    toggle = { knobOn = Hex("#06231B") },
    progress = { variant = "segments", segments = 18, gap = 2, height = 10, radius = 2,
        ramp = { Hex("#5EF2C2"), Hex("#4FD1E8"), Hex("#8B7CFF"), Hex("#C77DFF") } },
    choice = { variant = "chips", pill = true, radius = 1 },
    icons = { alt = Hex("#8B7CFF") },
}

local FROST = {
    name = "Frost", subtitle = "Ice over glass", icon = "map",
    footer = "Frosted ice-blue glass with a white rim, a glacier ramp and glints that come and go.",
    palette = { bg = Hex("#EAF6FF", 0.84), text = Hex("#04263D"), muted = Hex("#24506E"), accent = Hex("#0E7FC0"),
        accentText = WHITE, danger = Hex("#C8323F"), surface = Hex("#FFFFFF", 0.75), line = Hex("#FFFFFF", 0.95),
        track = Hex("#C3DFF1") },
    panel = { radius = 14, blur = 16, rim = { light = Hex("#FFFFFF", 0.95), dark = Hex("#7FB8DA", 0.6) } },
    button = { radius = 10, secondaryEdge = Hex("#FFFFFF", 0.95) },
    title = { typeface = "Light", size = 26, spacing = 30 },
    data = { typeface = "Regular", size = 30, color = Hex("#075C8E") },
    toggle = { trackOff = Hex("#C3DFF1"), knobOff = Hex("#4F86AD") },
    slider = { thumbEdge = Hex("#0E7FC0") },
    progress = { variant = "segments", segments = 14, gap = 2, height = 10, radius = 2, track = Hex("#D3E9F6"),
        ramp = { Hex("#9ADCF7"), Hex("#4CB8EA"), Hex("#1593D6"), Hex("#0B6FA8") } },
    choice = { variant = "chips", pill = true, radius = 1, edge = Hex("#9CC9E6") },
    field = { fill = Hex("#FFFFFF", 0.8), outline = Hex("#9CC9E6") },
    icons = { tint = Hex("#0E7FC0"), alt = Hex("#24506E") },
    motion = { sparkle = true },
    hoverToward = WHITE, hoverAmount = 0.2,
}

local MIDNIGHT = {
    name = "Midnight", subtitle = "Calm and low contrast", icon = "user",
    footer = "Blue-black with soft periwinkle and pink, the palette of a late-night code editor.",
    palette = { bg = Hex("#0D1117", 0.97), text = Hex("#C9D1E3"), muted = Hex("#6E7894"), accent = Hex("#7AA2F7"),
        accentText = Hex("#0D1117"), danger = Hex("#F7768E"), dangerText = Hex("#0D1117"), surface = Hex("#1A2030"),
        line = Hex("#232A3B"), track = Hex("#1A2030") },
    panel = { radius = 12 },
    data = { font = "inconsolata", typeface = "Inconsolata SemiBold", size = 24 },
    toggle = { knobOn = Hex("#0D1117"), trackOff = Hex("#2A3247") },
    progress = { height = 4, radius = 2 },
    choice = { variant = "tabs" },
    icons = { alt = Hex("#BB9AF7") },
}

local STORM_FRONT = {
    name = "Storm Front", subtitle = "Lightning on violet", icon = "bolt",
    footer = "Lightning yellow on storm violet, with pill buttons and a violet-to-yellow bar.",
    palette = { bg = Hex("#1C1B2E", 0.97), text = Hex("#ECEAF7"), muted = Hex("#9A96B8"), accent = Hex("#FFE45C"),
        accentText = Hex("#1C1B2E"), danger = Hex("#FF5C7A"), surface = Hex("#2A2842"), line = Hex("#34314F"),
        track = Hex("#2A2842") },
    panel = { radius = 14 },
    button = { pill = true, radius = 1 },
    title = { font = "kanit", typeface = "Bold", size = 24 },
    body = { font = "kanit", typeface = "Default" },
    data = { font = "kanit", typeface = "Bold", size = 26 },
    toggle = { knobOn = Hex("#1C1B2E") },
    progress = { variant = "segments", segments = 16, gap = 2, height = 10, radius = 2,
        ramp = { Hex("#6F5CE0"), Hex("#9D8CFF"), Hex("#FFE45C") } },
    choice = { variant = "chips", pill = true, radius = 1 },
    icons = { alt = Hex("#9D8CFF") },
}

local SAKURA = {
    name = "Sakura", subtitle = "Soft and light", icon = "crown",
    footer = "Blush white and cherry pink, pill shapes and a rose shadow.",
    palette = { bg = Hex("#FFF5F7"), text = Hex("#3A2430"), muted = Hex("#8C6B7A"), accent = Hex("#E85D8A"),
        accentText = WHITE, danger = Hex("#C0392B"), surface = Hex("#FBE3EA"), line = Hex("#F3D3DD"),
        track = Hex("#F6DCE4") },
    panel = { radius = 16, width = 0, shadow = { color = Hex("#B0476A"), layers = { { 0.22, 3 }, { 0.12, 7 }, { 0.06, 12 } } } },
    button = { pill = true, radius = 1 },
    title = { font = "kanit", typeface = "Semibold", size = 24 },
    data = { font = "kanit", typeface = "Semibold", size = 26 },
    toggle = { trackOff = Hex("#EFCFDA") },
    choice = { variant = "chips", pill = true, radius = 1 },
    field = { fill = WHITE },
    hoverToward = BLACK, hoverAmount = 0.06,
}

local OCEAN = {
    name = "Ocean", subtitle = "Deep water", icon = "map",
    footer = "Deep teal with aqua, soft tinted buttons and large light numerals.",
    palette = { bg = Hex("#0B2A33", 0.97), text = Hex("#E3F6F5"), muted = Hex("#7FA9AD"), accent = Hex("#3FE0D0"),
        accentText = Hex("#062226"), danger = Hex("#FF5D73"), surface = Hex("#123A45"), line = Hex("#1A4A56"),
        track = Hex("#123A45") },
    panel = { radius = 18 },
    button = { variant = "soft", radius = 12 },
    title = { typeface = "Light", size = 24, spacing = 30 },
    data = { typeface = "Light", size = 30 },
    toggle = { knobOn = Hex("#062226") },
    progress = { height = 10, radius = 5 },
    choice = { variant = "joined", radius = 12 },
}

local STEEL = {
    name = "Steel", subtitle = "Brushed metal", icon = "fuel",
    footer = "Light metal grey with a bevel, outlined buttons and a blue accent.",
    palette = { bg = Hex("#C9CED4"), text = Hex("#1C232B"), muted = Hex("#4B5560"), accent = Hex("#2B6CB0"),
        accentText = WHITE, danger = Hex("#B83232"), surface = Hex("#DDE1E6"), line = Hex("#8E969F"),
        track = Hex("#AEB5BD") },
    panel = { radius = 6, bevel = true },
    button = { radius = 4, edge = Hex("#6E767F"), width = 1 },
    title = { font = "kanit", typeface = "Semibold", size = 22 },
    data = { font = "kanit", typeface = "Semibold", size = 24 },
    toggle = { variant = "square", trackOff = Hex("#9EA6AF") },
    slider = { thumb = "square", thumbFill = Hex("#DDE1E6"), thumbEdge = Hex("#6E767F") },
    progress = { variant = "segments", segments = 12, gap = 2, height = 10, radius = 1 },
    choice = { variant = "joined", radius = 4 },
    field = { fill = Hex("#E6E9ED"), outline = Hex("#8E969F") },
    hoverToward = WHITE, hoverAmount = 0.25,
}

local PAPER_SAGE = {
    name = "Paper", subtitle = "Sage green", icon = "crown",
    footer = "The light Paper layout in pale sage and deep green, with a green offset shadow.",
    palette = { bg = Hex("#F2F5F1"), text = Hex("#1F2A24"), muted = Hex("#5F6E64"), accent = Hex("#2E7D5B"),
        accentText = WHITE, danger = Hex("#B23A3A"), surface = Hex("#E2E9E1"), line = Hex("#D0DACF"),
        track = Hex("#D7E0D6") },
    panel = { radius = 6, shadow = { color = Hex("#20352A"), layers = { { 0.28, 3 }, { 0.16, 7 }, { 0.07, 12 } } } },
    button = { radius = 4 },
    title = { font = "kanit", typeface = "Semibold", size = 24 },
    data = { font = "kanit", typeface = "Bold", size = 22 },
    toggle = { trackOff = Hex("#C8D3C7") },
    hoverToward = BLACK, hoverAmount = 0.08,
}

------------------------------------------------------------------------------------------
-- Popular editor palettes, with their published colours
------------------------------------------------------------------------------------------

local DRACULA = {
    name = "Dracula", subtitle = "The Dracula palette", icon = "emotion",
    footer = "Dracula's background and comment blue-grey, purple as the accent, pink, cyan and green beside it.",
    palette = { bg = Hex("#282A36", 0.97), text = Hex("#F8F8F2"), muted = Hex("#6272A4"), accent = Hex("#BD93F9"),
        accentText = Hex("#282A36"), danger = Hex("#FF5555"), dangerText = Hex("#282A36"), surface = Hex("#44475A"),
        line = Hex("#44475A"), track = Hex("#44475A") },
    panel = { radius = 10 },
    title = { size = 22 },
    data = { color = Hex("#FF79C6") },
    toggle = { trackOff = Hex("#44475A"), knobOn = Hex("#282A36") },
    progress = { variant = "segments", segments = 16, gap = 2, height = 10, radius = 2,
        ramp = { Hex("#8BE9FD"), Hex("#50FA7B"), Hex("#F1FA8C"), Hex("#FF79C6"), Hex("#BD93F9") } },
    section = { color = Hex("#FF79C6") },
    icons = { tint = Hex("#FF79C6"), alt = Hex("#8BE9FD") },
}

local MOCHA = {
    name = "Catppuccin Mocha", subtitle = "Soothing pastel, dark", icon = "emotion",
    footer = "Mocha's base, surfaces and text, mauve as the accent, and the blue to pink pastels.",
    palette = { bg = Hex("#1E1E2E", 0.97), text = Hex("#CDD6F4"), muted = Hex("#A6ADC8"), accent = Hex("#CBA6F7"),
        accentText = Hex("#11111B"), danger = Hex("#F38BA8"), dangerText = Hex("#11111B"), surface = Hex("#313244"),
        line = Hex("#45475A"), track = Hex("#313244") },
    panel = { radius = 14 },
    button = { radius = 10 },
    title = { font = "kanit", typeface = "Semibold", size = 22 },
    data = { font = "kanit", typeface = "Semibold", size = 24, color = Hex("#89B4FA") },
    toggle = { trackOff = Hex("#45475A"), knobOn = Hex("#11111B") },
    progress = { variant = "segments", segments = 16, gap = 2, height = 10, radius = 3,
        ramp = { Hex("#89B4FA"), Hex("#B4BEFE"), Hex("#CBA6F7"), Hex("#F5C2E7") } },
    choice = { variant = "chips", pill = true, radius = 1 },
    section = { color = Hex("#B4BEFE") },
    icons = { tint = Hex("#F5C2E7"), alt = Hex("#89DCEB") },
}

local LATTE = {
    name = "Catppuccin Latte", subtitle = "Soothing pastel, light", icon = "emotion",
    footer = "Latte, Catppuccin's light flavour: its base and surfaces, mauve, pink and blue.",
    palette = { bg = Hex("#EFF1F5"), text = Hex("#4C4F69"), muted = Hex("#6C6F85"), accent = Hex("#8839EF"),
        accentText = Hex("#EFF1F5"), danger = Hex("#D20F39"), surface = Hex("#CCD0DA"), line = Hex("#BCC0CC"),
        track = Hex("#CCD0DA") },
    panel = { radius = 14, shadow = { color = Hex("#4C4F69"), layers = { { 0.18, 3 }, { 0.10, 7 }, { 0.05, 12 } } } },
    button = { radius = 10 },
    title = { font = "kanit", typeface = "Semibold", size = 22 },
    data = { font = "kanit", typeface = "Semibold", size = 24, color = Hex("#1E66F5") },
    toggle = { trackOff = Hex("#BCC0CC") },
    choice = { variant = "chips", pill = true, radius = 1 },
    section = { color = Hex("#7287FD") },
    icons = { tint = Hex("#EA76CB"), alt = Hex("#1E66F5") },
    hoverToward = BLACK, hoverAmount = 0.08,
}

local MATERIAL = {
    name = "Material", subtitle = "Material Design, dark", icon = "user",
    footer = "Material's dark surface, purple primary and teal secondary, capital button labels, tabs.",
    palette = { bg = Hex("#1E1E1E", 0.98), text = Hex("#E1E1E1"), muted = Hex("#9E9E9E"), accent = Hex("#BB86FC"),
        accentText = BLACK, danger = Hex("#CF6679"), dangerText = BLACK, surface = Hex("#2C2C2C"), line = Hex("#333333"),
        track = Hex("#3A3A3A") },
    panel = { radius = 4, width = 0, shadow = { color = BLACK, layers = { { 0.35, 2 }, { 0.22, 6 }, { 0.12, 12 } } } },
    button = { radius = 4, upper = true, spacing = 90, typeface = "Bold",
        roles = { primary = "fill", secondary = "ghost", danger = "ghost" } },
    title = { typeface = "Regular", size = 22 },
    data = { typeface = "Regular", size = 24, color = Hex("#03DAC6") },
    toggle = { trackOn = Hex("#BB86FC", 0.5), knobOn = Hex("#BB86FC"), trackOff = Hex("#5C5C5C"), knobOff = Hex("#BDBDBD") },
    slider = { thumbFill = Hex("#BB86FC"), thumbEdge = Hex("#BB86FC") },
    progress = { height = 4, radius = 0 },
    choice = { variant = "tabs" },
    section = { color = Hex("#BB86FC") },
    icons = { alt = Hex("#03DAC6") },
}

local MONOKAI = {
    name = "Monokai", subtitle = "The classic editor theme", icon = "map",
    footer = "Monokai's olive-black background with its green, blue, yellow and pink, readings in Inconsolata.",
    palette = { bg = Hex("#272822", 0.97), text = Hex("#F8F8F2"), muted = Hex("#75715E"), accent = Hex("#A6E22E"),
        accentText = Hex("#272822"), danger = Hex("#F92672"), surface = Hex("#3E3D32"), line = Hex("#49483E"),
        track = Hex("#3E3D32") },
    panel = { radius = 6 },
    button = { radius = 4 },
    data = { font = "inconsolata", typeface = "Inconsolata SemiBold", size = 24, color = Hex("#E6DB74") },
    toggle = { knobOn = Hex("#272822") },
    progress = { variant = "segments", segments = 15, gap = 2, height = 10, radius = 1,
        ramp = { Hex("#66D9EF"), Hex("#A6E22E"), Hex("#E6DB74"), Hex("#FD971F"), Hex("#F92672") } },
    choice = { variant = "tabs" },
    section = { color = Hex("#66D9EF") },
    icons = { tint = Hex("#66D9EF"), alt = Hex("#AE81FF") },
}

local NORD = {
    name = "Nord", subtitle = "Arctic, north-bluish", icon = "map",
    footer = "Nord's polar night greys, snow storm text and frost blues, with aurora red for danger.",
    palette = { bg = Hex("#2E3440", 0.97), text = Hex("#ECEFF4"), muted = Hex("#9AA5B8"), accent = Hex("#88C0D0"),
        accentText = Hex("#2E3440"), danger = Hex("#BF616A"), surface = Hex("#3B4252"), line = Hex("#434C5E"),
        track = Hex("#434C5E") },
    panel = { radius = 8 },
    button = { radius = 6 },
    data = { color = Hex("#8FBCBB") },
    toggle = { knobOn = Hex("#2E3440"), trackOff = Hex("#4C566A") },
    section = { color = Hex("#81A1C1") },
    icons = { tint = Hex("#88C0D0"), alt = Hex("#B48EAD") },
}

------------------------------------------------------------------------------------------
-- Operating system styles, light and dark. Each imitates the look with the shapes and fonts
-- available here; none uses the operating system's own fonts or images.
------------------------------------------------------------------------------------------

-- Windows Classic bevels. Raised, as on a button: the outer ring is light grey at the top left
-- and near-black at the bottom right, the inner ring white and dark grey. The sunken table is
-- written so that drawing it sunken (light and dark swapped) gives the outer ring dark grey and
-- white, and the inner ring near-black and light grey, as on a field or a progress trough.
local CLASSIC_RAISED = { light = Hex("#DFDFDF"), dark = Hex("#0A0A0A"), innerLight = WHITE, innerDark = Hex("#808080") }
local CLASSIC_SUNKEN = { light = WHITE, dark = Hex("#808080"), innerLight = Hex("#DFDFDF"), innerDark = Hex("#0A0A0A") }

-- macOS System Settings icon tiles: top and bottom colours of each rounded square.
local MAC_TILES = {
    { Hex("#5AB8FF"), Hex("#0A7AFF") },
    { Hex("#FF8A80"), Hex("#F2362B") },
    { Hex("#C08BFF"), Hex("#8E44E8") },
    { Hex("#FFC24D"), Hex("#FF9500") },
    { Hex("#6EDC78"), Hex("#2DB84C") },
    { Hex("#C7C7CC"), Hex("#8E8E93") },
}

local WIN11_FACE = { fill = Hex("#FEFEFE"), text = Hex("#1B1B1B") }
local WIN11_LIGHT = {
    name = "Windows 11", subtitle = "Settings", icon = "user",
    footer = "Fluent, light: a flush title bar with full-height caption buttons, #FEFEFE buttons, monochrome icons.",
    palette = { bg = Hex("#F0F3F9", 0.99), text = Hex("#1B1B1B"), muted = Hex("#5D5D5D"), accent = Hex("#0070D5"),
        accentText = WHITE, danger = Hex("#C42B1C"), surface = Hex("#FEFEFE"), line = Hex("#E5E5E5"),
        track = Hex("#8A8A8A") },
    panel = { radius = 8, header = "window", outline = Hex("#DADDE3"),
        shadow = { color = BLACK, layers = { { 0.14, 3 }, { 0.08, 8 }, { 0.04, 14 } } } },
    button = { radius = 4, secondaryEdge = Hex("#E1E1E1"), height = 32, faces = { secondary = WIN11_FACE, danger = WIN11_FACE } },
    title = { typeface = "Bold", size = 26 },
    data = { typeface = "Regular", size = 22, color = Hex("#1B1B1B") },
    toggle = { w = 40, h = 20, offEdge = Hex("#8A8A8A"), knobOff = Hex("#5D5D5D") },
    slider = { thumbFill = Hex("#0070D5"), thumbEdge = WHITE, thumbHover = Hex("#1A82DE"), size = 20, thumbWidth = 4 },
    progress = { height = 3, radius = 2, track = Hex("#D1D1D1") },
    choice = { variant = "tabs", markWidth = 16, markHeight = 3, tabText = Hex("#1B1B1B") },
    field = { fill = Hex("#FEFEFE"), outline = Hex("#E5E5E5"), radius = 4 },
    section = { color = Hex("#1B1B1B") },
    icons = { tint = Hex("#1B1B1B"), alt = Hex("#1B1B1B") },
    hoverToward = BLACK, hoverAmount = 0.06,
}

local WIN11_DARK_FACE = { fill = Hex("#2D2D2D"), text = WHITE }
local WIN11_DARK = {
    name = "Windows 11", subtitle = "Settings", icon = "user",
    footer = "Fluent, dark: charcoal Mica, #2D2D2D buttons with a faint edge, the dark theme's light blue accent.",
    palette = { bg = Hex("#202020", 0.99), text = WHITE, muted = Hex("#C8C8C8"), accent = Hex("#4CC2FF"),
        accentText = BLACK, danger = Hex("#FF99A4"), surface = Hex("#2D2D2D"), line = Hex("#333333"),
        track = Hex("#9A9A9A") },
    panel = { radius = 8, header = "window", outline = Hex("#3A3A3A"),
        shadow = { color = BLACK, layers = { { 0.30, 3 }, { 0.18, 8 }, { 0.08, 14 } } } },
    button = { radius = 4, secondaryEdge = Hex("#3A3A3A"), height = 32,
        faces = { secondary = WIN11_DARK_FACE, danger = WIN11_DARK_FACE } },
    title = { typeface = "Bold", size = 26 },
    data = { typeface = "Regular", size = 22, color = WHITE },
    toggle = { w = 40, h = 20, offEdge = Hex("#9A9A9A"), knobOff = Hex("#CFCFCF"), knobOn = BLACK },
    slider = { thumbFill = Hex("#4CC2FF"), thumbEdge = Hex("#454545"), thumbHover = Hex("#6FCEFF"), size = 20, thumbWidth = 4 },
    progress = { height = 3, radius = 2, track = Hex("#5A5A5A") },
    choice = { variant = "tabs", markWidth = 16, markHeight = 3, tabText = WHITE },
    field = { fill = Hex("#2D2D2D"), outline = Hex("#3A3A3A"), radius = 4 },
    section = { color = WHITE },
    icons = { tint = WHITE, alt = WHITE },
    hoverToward = WHITE, hoverAmount = 0.06,
}

local MAC_LIGHT = {
    name = "macOS", subtitle = "System Settings", icon = "user",
    footer = "A light macOS window: traffic lights that show their symbols on hover, gradient icon tiles, a segmented control.",
    palette = { bg = Hex("#F6F6F6", 0.92), text = Hex("#1D1D1F"), muted = Hex("#6E6E73"), accent = Hex("#007AFF"),
        accentText = WHITE, danger = Hex("#FF3B30"), surface = WHITE, line = Hex("#D9D9DE"), track = Hex("#C8C8CC") },
    panel = { radius = 12, header = "mac", blur = 12, outline = Hex("#D1D1D6"),
        shadow = { color = BLACK, layers = { { 0.12, 4 }, { 0.07, 10 }, { 0.04, 18 } } } },
    button = { radius = 6, secondaryEdge = Hex("#D1D1D6") },
    title = { typeface = "Bold", size = 15 },
    data = { typeface = "Regular", size = 22, color = Hex("#1D1D1F") },
    toggle = { trackOff = Hex("#D1D1D6") },
    slider = { thumbFill = WHITE, thumbEdge = Hex("#B4B4B9"), thumbHover = WHITE, size = 20, thumbWidth = 1 },
    progress = { height = 6, radius = 3, track = Hex("#DCDCE0") },
    choice = { variant = "joined", radius = 6, trackFill = Hex("#E3E3E8"), markFill = WHITE, markText = Hex("#1D1D1F"),
        markEdge = Hex("#D1D1D6") },
    field = { fill = WHITE, outline = Hex("#D1D1D6"), radius = 6 },
    section = { color = Hex("#6E6E73") },
    icons = { tiles = MAC_TILES },
    hoverToward = BLACK, hoverAmount = 0.06,
}

local MAC_DARK = {
    name = "macOS", subtitle = "System Settings, dark", icon = "user",
    footer = "The macOS window in dark mode: graphite vibrancy, gradient icon tiles, a grey segmented control.",
    palette = { bg = Hex("#1E1E1E", 0.86), text = Hex("#F5F5F7"), muted = Hex("#98989D"), accent = Hex("#0A84FF"),
        accentText = WHITE, danger = Hex("#FF453A"), surface = Hex("#3A3A3C"), line = Hex("#38383A"),
        track = Hex("#5A5A5E") },
    panel = { radius = 12, header = "mac", blur = 12, outline = Hex("#4A4A4C"),
        shadow = { color = BLACK, layers = { { 0.30, 4 }, { 0.18, 10 }, { 0.08, 18 } } } },
    button = { radius = 6, secondaryEdge = Hex("#545458") },
    title = { typeface = "Bold", size = 15 },
    data = { typeface = "Regular", size = 22, color = Hex("#F5F5F7") },
    toggle = { trackOff = Hex("#48484C") },
    slider = { thumbFill = Hex("#D8D8DC"), thumbEdge = Hex("#636366"), thumbHover = WHITE, size = 20, thumbWidth = 1 },
    progress = { height = 6, radius = 3, track = Hex("#3A3A3C") },
    choice = { variant = "joined", radius = 6, trackFill = Hex("#2C2C2E"), markFill = Hex("#636366"),
        markText = Hex("#F5F5F7") },
    field = { fill = Hex("#2C2C2E"), outline = Hex("#48484A"), radius = 6 },
    section = { color = Hex("#98989D") },
    icons = { tiles = MAC_TILES },
    hoverToward = WHITE, hoverAmount = 0.08,
}

local XP_FACE = { fill = Hex("#F4F3EE"), text = BLACK }
local XP_LIGHT = {
    name = "Windows XP", subtitle = "Luna blue", icon = "user",
    footer = "Luna: a glossy title bar with bubble caption buttons, 3D push buttons, green blocks in a rounded trough.",
    palette = { bg = Hex("#ECE9D8"), text = BLACK, muted = Hex("#4D4D4D"), accent = Hex("#316AC5"), accentText = WHITE,
        danger = Hex("#C1272D"), surface = Hex("#F4F3EE"), line = Hex("#ACA899"), track = WHITE },
    panel = { radius = 8, radii = { 8, 8, 0, 0 }, width = 3, outline = Hex("#0831D9"), header = "xpbar", pad = 14,
        barStops = { Hex("#5AA6FF"), Hex("#3189FA"), Hex("#0F69EA"), Hex("#0058E6"), Hex("#0056E5"), Hex("#0054E2"),
            Hex("#0052DE"), Hex("#004CD0"), Hex("#003FB8") },
        controlStops = { Hex("#D8E6FF"), Hex("#7BA8F6"), Hex("#3C78EA"), Hex("#2560D8"), Hex("#2257CB"), Hex("#3A72E0") },
        closeStops = { Hex("#F8C8B4"), Hex("#EE8A68"), Hex("#E2582E"), Hex("#CC4218"), Hex("#C23B12"), Hex("#D9542A") },
        titleShadow = Hex("#0F1089"),
        statusBar = { text = "Ready", fill = Hex("#ECE9D8"), line = Hex("#C5C2B2") } },
    button = { variant = "xp", radius = 3, height = 28,
        faces = { primary = XP_FACE, secondary = XP_FACE, danger = XP_FACE },
        xp = { edge = Hex("#003C74"), glow = Hex("#F8B33A"), defaultRing = Hex("#8CB4F0"),
            face = { WHITE, WHITE, Hex("#F7F6F2"), Hex("#EEEDE7"), Hex("#E3E0D7"), Hex("#D6D0C5") },
            pressedFace = { Hex("#CDC9B8"), Hex("#DCD9CC"), Hex("#E6E4DA"), Hex("#EFEEE7") } } },
    title = { typeface = "Bold", size = 15 },
    data = { typeface = "Bold", size = 18, color = BLACK },
    toggle = { variant = "check", radius = 0, checkOff = WHITE, checkOn = WHITE, checkEdge = Hex("#1C5180"),
        checkEdgeOn = Hex("#1C5180"), checkMark = Hex("#21A121"), checkEdgeWidth = 1 },
    slider = { thumb = "bar", thumbFill = Hex("#F4F3EE"), thumbEdge = Hex("#003C74"), thumbHover = WHITE,
        track = Hex("#ACA899"), thickness = 3 },
    progress = { variant = "segments", segments = 18, gap = 2, height = 12, radius = 1, track = WHITE,
        block = { Hex("#A6F09C"), Hex("#5BDB50"), Hex("#37D52C"), Hex("#2DB320"), Hex("#3AC22E") },
        frame = { edge = Hex("#686868"), radius = 4, pad = 2, fill = WHITE } },
    choice = { variant = "radio", radioEdge = Hex("#1C5180"), radioFill = WHITE, markFill = Hex("#21A121") },
    field = { fill = WHITE, outline = Hex("#7F9DB9"), radius = 0 },
    section = { color = Hex("#215DC6") },
    icons = { tint = Hex("#316AC5"), alt = Hex("#2EB82E") },
}

local NOIR_FACE = { fill = Hex("#F2F2F2"), text = BLACK }
local XP_NOIR = {
    name = "Windows XP", subtitle = "Royale Noir", icon = "user",
    footer = "Royale Noir: glossy black chrome and black bubble caption buttons over a light body.",
    palette = { bg = Hex("#EFEFEF"), text = BLACK, muted = Hex("#4A4A4A"), accent = Hex("#5F7FD4"), accentText = WHITE,
        danger = Hex("#B8282E"), surface = Hex("#F2F2F2"), line = Hex("#A0A0A0"), track = WHITE },
    panel = { radius = 8, radii = { 8, 8, 0, 0 }, width = 3, outline = Hex("#1A1A1A"), header = "xpbar", pad = 14,
        barStops = { Hex("#5C5C5C"), Hex("#3A3A3A"), Hex("#242424"), Hex("#161616"), Hex("#0E0E0E"), Hex("#090909"),
            Hex("#050505"), Hex("#0C0C0C"), Hex("#1A1A1A") },
        controlStops = { Hex("#9A9A9A"), Hex("#5A5A5A"), Hex("#2E2E2E"), Hex("#1A1A1A"), Hex("#141414"), Hex("#2A2A2A") },
        closeStops = { Hex("#F8C8B4"), Hex("#EE8A68"), Hex("#E2582E"), Hex("#CC4218"), Hex("#C23B12"), Hex("#D9542A") },
        titleShadow = BLACK,
        statusBar = { text = "Ready", fill = Hex("#EFEFEF"), line = Hex("#BDBDBD") } },
    button = { variant = "xp", radius = 3, height = 28,
        faces = { primary = NOIR_FACE, secondary = NOIR_FACE, danger = NOIR_FACE },
        xp = { edge = Hex("#1C1C1C"), glow = Hex("#F8B33A"), defaultRing = Hex("#5F7FD4"),
            face = { WHITE, WHITE, Hex("#F7F7F7"), Hex("#EDEDED"), Hex("#E0E0E0"), Hex("#D0D0D0") },
            pressedFace = { Hex("#C8C8C8"), Hex("#D8D8D8"), Hex("#E4E4E4"), Hex("#EEEEEE") } } },
    title = { typeface = "Bold", size = 15 },
    data = { typeface = "Bold", size = 18, color = BLACK },
    toggle = { variant = "check", radius = 0, checkOff = WHITE, checkOn = WHITE, checkEdge = Hex("#333333"),
        checkEdgeOn = Hex("#333333"), checkMark = Hex("#21A121"), checkEdgeWidth = 1 },
    slider = { thumb = "bar", thumbFill = Hex("#F2F2F2"), thumbEdge = Hex("#1C1C1C"), thumbHover = WHITE,
        track = Hex("#A0A0A0"), thickness = 3 },
    progress = { variant = "segments", segments = 18, gap = 2, height = 12, radius = 1, track = WHITE,
        block = { Hex("#A6F09C"), Hex("#5BDB50"), Hex("#37D52C"), Hex("#2DB320"), Hex("#3AC22E") },
        frame = { edge = Hex("#4A4A4A"), radius = 4, pad = 2, fill = WHITE } },
    choice = { variant = "radio", radioEdge = Hex("#333333"), radioFill = WHITE, markFill = Hex("#21A121") },
    field = { fill = WHITE, outline = Hex("#7A7A7A"), radius = 0 },
    section = { color = Hex("#3A3A3A") },
    icons = { tint = Hex("#3A3A3A"), alt = Hex("#5F7FD4") },
}
local CLASSIC_FACE = { fill = Hex("#C0C0C0"), text = BLACK }
local CLASSIC = {
    name = "Windows 98", subtitle = "Windows Classic", icon = "user",
    footer = "Two-ring 3D bevels that press in, a navy-to-blue title bar, radio buttons, a sunken trough of navy blocks.",
    palette = { bg = Hex("#C0C0C0"), text = BLACK, muted = Hex("#404040"), accent = Hex("#000080"), accentText = WHITE,
        danger = Hex("#800000"), surface = Hex("#C0C0C0"), line = Hex("#808080"), track = WHITE },
    panel = { radius = 0, width = 0, header = "classic", bevel = CLASSIC_RAISED, bandInset = 3, pad = 12,
        barStops = { Hex("#000080"), Hex("#1084D0") } },
    button = { variant = "classic", radius = 0, bevel = CLASSIC_RAISED, height = 30,
        faces = { primary = CLASSIC_FACE, secondary = CLASSIC_FACE, danger = CLASSIC_FACE } },
    title = { typeface = "Bold", size = 13 },
    body = { size = 13 },
    data = { typeface = "Bold", size = 16, color = BLACK },
    toggle = { variant = "check", radius = 0, checkOff = WHITE, checkOn = WHITE, checkEdgeWidth = 0, checkMark = BLACK,
        checkBevel = CLASSIC_SUNKEN },
    slider = { thumb = "bar", thumbFill = Hex("#C0C0C0"), thumbEdge = BLACK, thumbHover = Hex("#C0C0C0"),
        track = Hex("#808080"), thickness = 4 },
    progress = { variant = "segments", segments = 16, gap = 2, height = 14, radius = 0, fill = Hex("#000080"), track = WHITE,
        frame = { fill = WHITE, pad = 2, bevel = CLASSIC_SUNKEN } },
    choice = { variant = "radio", radioEdge = Hex("#808080"), radioFill = WHITE, markFill = BLACK },
    field = { fill = WHITE, outline = WHITE, radius = 0, bevel = CLASSIC_SUNKEN },
    section = { color = BLACK },
    icons = { tint = Hex("#000080"), alt = Hex("#808080") },
}

local PAGES = {
    { key = "F6", title = "Favourites 1", layout = "deep", themes = { SLATE, GLASS, STORM, NEON } },
    { key = "F7", title = "Favourites 2", layout = "deep", themes = { DOPPLER, WARNING, NIGHT, LOADOUT } },
    { key = "F8", title = "Favourites 3", layout = "deep", themes = { COZY, CARBON, BLUEPRINT, MIXED } },
    { key = "F9", title = "Reworked", layout = "compact", themes = { TERMINAL, PAPER_BLUE, FIELD_KIT, HOLOGRAM, INK, FROST } },
    { key = "F10", title = "New", layout = "wide", themes = { AURORA, MIDNIGHT, STORM_FRONT, SAKURA, OCEAN, STEEL, PAPER_SAGE } },
    { key = "F11", title = "Palettes", layout = "compact", themes = { DRACULA, MOCHA, LATTE, MATERIAL, MONOKAI, NORD } },
    { key = "F12", title = "Operating systems", layout = "wide",
        themes = { WIN11_LIGHT, MAC_LIGHT, XP_LIGHT, CLASSIC, WIN11_DARK, MAC_DARK, XP_NOIR } },
}

-- Card rectangles per layout, as fractions of the screen: columns, rows, and the gaps between them.
local LAYOUTS = {
    deep = { cols = 2, rows = 2, x0 = 0.02, y0 = 0.075, w = 0.47, h = 0.445, dx = 0.49, dy = 0.465 },
    compact = { cols = 3, rows = 2, x0 = 0.02, y0 = 0.075, w = 0.31, h = 0.445, dx = 0.325, dy = 0.465 },
    wide = { cols = 4, rows = 2, x0 = 0.012, y0 = 0.075, w = 0.235, h = 0.445, dx = 0.2455, dy = 0.465 },
}

------------------------------------------------------------------------------------------
-- Object builders, one per object type
------------------------------------------------------------------------------------------

local function Caption(s, str)
    if s.upper then
        return string.upper(str)
    end
    return str
end

local function BodyText(s, str, color, size, extra)
    local spec = Merge(s.body, extra)
    spec.color = color or s.body.color
    spec.size = size or s.body.size
    if spec.shadow == nil then
        spec.shadow = s.textShadow
    end
    return Text(s.name, Caption(s, str), spec)
end

local function RoleColors(s, role)
    local p = s.p
    local face = s.button.faces and s.button.faces[role]
    if face ~= nil then
        return face.fill, face.text
    end
    if role == "primary" then
        return p.accent, p.accentText
    elseif role == "danger" then
        return p.danger, p.dangerText
    end
    return p.surface, p.secondaryText
end

local function Pop(card)
    card.popAt = os.clock()
end

local function Shake(card)
    card.shakeAt = os.clock()
end

--- Wrap a widget in a hard offset shadow: a solid block behind it, shifted down and right.
local function HardShadow(s, widget, hard)
    local wrap = New("Overlay")
    local block = Box(s.name, { fill = hard.color }, 0)
    OAdd(wrap, block, { hard.d, hard.d, 0, 0 })
    OAdd(wrap, widget, { 0, 0, hard.d, hard.d })
    return wrap
end

--- Bevel lines over a widget: light along the top and left edges and dark along the bottom and
--- right, or the reverse when sunken. bv: light, dark, and optionally innerLight and innerDark for a
--- second ring one pixel in, as in Windows Classic.
local function BevelLines(name, o, bv, sunken)
    local lines = {}
    local w = bv.width or 1
    local function Line(color, width, height, pad, h, v)
        local line = Sized(Box(name, { fill = color }, 0), width, height)
        OAdd(o, line, pad, h, v)
        lines[#lines + 1] = line
    end
    local function Ring(light, dark, inset)
        if sunken then
            light, dark = dark, light
        end
        Line(light, nil, w, { inset, inset, inset, 0 }, H_FILL, V_TOP)
        Line(light, w, nil, { inset, inset, 0, inset }, H_LEFT, V_FILL)
        Line(dark, nil, w, { inset, 0, inset, inset }, H_FILL, V_BOTTOM)
        Line(dark, w, nil, { 0, inset, inset, inset }, H_RIGHT, V_FILL)
    end
    Ring(bv.light, bv.dark, 0)
    if bv.innerLight ~= nil then
        Ring(bv.innerLight, bv.innerDark, w)
    end
    return lines
end

local function Bevel(name, widget, bv, sunken)
    local o = New("Overlay")
    OAdd(o, widget)
    BevelLines(name, o, bv, sunken)
    return o
end

--- A small repeatable random number generator, so each card's noise and glitches follow their own
--- pattern. g is a table holding the seed.
local function Rand(g)
    g.seed = (g.seed * 1103515245 + 12345) % 2147483648
    return g.seed / 2147483648
end

--- A colour ramp of n steps through the given stops, for faking a gradient from strips.
local function Ramp(stops, n)
    local out = {}
    for i = 1, n do
        local t = (n == 1) and 0 or (i - 1) / (n - 1) * (#stops - 1)
        local k = math.min(#stops - 1, math.floor(t))
        out[i] = Mix(stops[k + 1], stops[math.min(#stops, k + 2)], t - k)
    end
    return out
end

--- A gradient faked from strips that share the available space evenly, so it stretches to any
--- size. Vertical runs top to bottom; horizontal runs left to right. With a radius, the end
--- strips are rounded on their outer corners and given a fixed size of at least the radius, so the
--- rounding has room; roundEnds "first" rounds only the first end, as on a title bar.
local function Gradient(name, stops, steps, radius, horizontal, roundEnds)
    local colors = Ramp(stops, steps or 12)
    local box = New(horizontal and "HorizontalBox" or "VerticalBox")
    local r = radius or 0
    for i, c in ipairs(colors) do
        local radii = { 0, 0, 0, 0 }
        local cap = false
        if r > 0 then
            if i == 1 then
                radii = horizontal and { r, 0, 0, r } or { r, r, 0, 0 }
                cap = true
            elseif i == #colors and roundEnds ~= "first" then
                radii = horizontal and { 0, r, r, 0 } or { 0, 0, r, r }
                cap = true
            end
        end
        local square = radii[1] == 0 and radii[2] == 0 and radii[3] == 0 and radii[4] == 0
        local strip = Box(name, { fill = c, radius = square and 0 or radii }, 0)
        local child = strip
        if cap then
            child = horizontal and Sized(strip, r, nil) or Sized(strip, nil, r)
        end
        local slot = horizontal and box:AddChildToHorizontalBox(child) or box:AddChildToVerticalBox(child)
        pcall(function()
            slot:SetSize({ SizeRule = cap and 0 or 1, Value = cap and 0 or 1 })
            if horizontal then
                slot:SetVerticalAlignment(V_FILL)
            else
                slot:SetHorizontalAlignment(H_FILL)
            end
        end)
    end
    return box
end

--- Watch a widget's hover and press state; fn(hovered, pressed) runs whenever either changes.
local function WatchHover(widget, fn)
    local list = S.buildTarget and S.buildTarget.hovers
    if list ~= nil then
        list[#list + 1] = { widget = widget, fn = fn, hovered = false, pressed = false }
    end
end

--- A button in the theme's style for its role: primary, secondary or danger.
local function MakeButton(card, s, role, caption, onClick, size)
    local b = s.button
    local variant = (b.roles and b.roles[role]) or b.variant
    local base, onBase = RoleColors(s, role)
    local edgeColor = role == "secondary" and s.p.text or base
    local r, pill = b.radius, b.pill
    local states, labelColor
    local clear = Alpha(edgeColor, 0)

    if variant == "fill" then
        states = {
            normal = { fill = base, radius = r, pill = pill },
            hovered = { fill = Mix(base, s.hoverToward, s.hoverAmount), radius = r, pill = pill },
            pressed = { fill = Mix(base, BLACK, 0.22), radius = r, pill = pill },
        }
        labelColor = onBase
    elseif variant == "soft" then
        states = {
            normal = { fill = Alpha(edgeColor, 0.14), radius = r, pill = pill },
            hovered = { fill = Alpha(edgeColor, 0.24), radius = r, pill = pill },
            pressed = { fill = Alpha(edgeColor, 0.34), radius = r, pill = pill },
        }
        labelColor = edgeColor
    elseif variant == "xp" or variant == "classic" then
        -- These draw every state themselves, from the hover and press watcher.
        local none = { fill = clear, radius = r }
        states = { normal = none, hovered = none, pressed = none }
        labelColor = onBase
    else -- ghost and underline: a transparent button that washes in on hover
        states = {
            normal = { fill = clear, radius = r, pill = pill },
            hovered = { fill = Alpha(edgeColor, 0.16), radius = r, pill = pill },
            pressed = { fill = Alpha(edgeColor, 0.30), radius = r, pill = pill },
        }
        labelColor = edgeColor
    end

    if b.upper then
        caption = string.upper(caption)
    end
    local label = BodyText(s, caption, labelColor, size or b.size, { justify = 1, spacing = b.spacing,
        typeface = b.typeface or s.body.typeface })
    local content, watch
    if variant == "underline" then
        local stack = New("VerticalBox")
        VAdd(stack, label, 0, H_CENTER)
        VAdd(stack, Sized(Box(s.name, { fill = edgeColor }, 0), nil, 2), { 0, 3, 0, 0 }, H_FILL)
        content = Box(s.name, { fill = clear }, 0)
        SetContentAligned(content, stack, H_CENTER, V_CENTER, { 12, 4, 12, 4 })
    elseif variant == "xp" then
        -- Windows XP: a dark rounded edge around a gradient face, an orange glow inside the edge on
        -- hover, and a darker face while pressed.
        local x = b.xp
        local stack = New("Overlay")
        local faceNormal = Gradient(s.name, x.face, 10, math.max(0, r - 1))
        local facePressed = Gradient(s.name, x.pressedFace, 10, math.max(0, r - 1))
        OAdd(stack, faceNormal, 1)
        OAdd(stack, facePressed, 1)
        -- The default button (primary) carries a blue inner ring; hover replaces it with the glow.
        local ring = nil
        if role == "primary" and x.defaultRing ~= nil then
            ring = Box(s.name, { fill = Alpha(x.defaultRing, 0), outline = x.defaultRing, width = 2,
                radius = math.max(0, r - 1) }, 0)
            OAdd(stack, ring, 1)
        end
        local glow = Box(s.name, { fill = Alpha(x.glow, 0), outline = x.glow, width = 2, radius = math.max(0, r - 1) }, 0)
        OAdd(stack, glow, 1)
        OAdd(stack, Box(s.name, { fill = Alpha(x.edge, 0), outline = x.edge, width = 1, radius = r }, 0))
        OAdd(stack, label, { 10, 4, 10, 4 }, H_CENTER, V_CENTER)
        SetShown(facePressed, false)
        SetShown(glow, false)
        content = stack
        watch = function(hovered, pressed)
            SetShown(glow, hovered and not pressed)
            if ring ~= nil then
                SetShown(ring, not hovered)
            end
            SetShown(faceNormal, not pressed)
            SetShown(facePressed, pressed)
        end
    elseif variant == "classic" then
        -- Windows Classic: a raised two-ring bevel that turns sunken while pressed, the caption
        -- moving one pixel down and right with it.
        local stack = New("Overlay")
        OAdd(stack, Box(s.name, { fill = base }, 0))
        local raised = BevelLines(s.name, stack, b.bevel, false)
        local sunken = BevelLines(s.name, stack, b.bevel, true)
        for _, line in ipairs(sunken) do
            SetShown(line, false)
        end
        OAdd(stack, label, { 10, 4, 10, 4 }, H_CENTER, V_CENTER)
        content = stack
        watch = function(_, pressed)
            for _, line in ipairs(raised) do
                SetShown(line, not pressed)
            end
            for _, line in ipairs(sunken) do
                SetShown(line, pressed)
            end
            pcall(function()
                label:SetRenderTranslation({ X = pressed and 1 or 0, Y = pressed and 1 or 0 })
            end)
        end
    else
        -- Ghost buttons and fill buttons with an edge draw the outline with a Border inside the button.
        local edge = b.edge
        if variant == "ghost" then
            edge = edgeColor
        elseif role == "secondary" and b.secondaryEdge ~= nil then
            edge = b.secondaryEdge
        end
        local width = edge ~= nil and (b.width or 1) or 0
        content = Box(s.name, { fill = clear, outline = edge, width = width, radius = r, pill = pill }, 0)
        SetContentAligned(content, label, H_CENTER, V_CENTER, { 10, 4, 10, 4 })
        if b.bevel ~= nil then
            content = Bevel(s.name, content, b.bevel)
        end
    end

    local button = Button(s.name, states, content, onClick)
    if watch ~= nil then
        WatchHover(button, watch)
    end
    local outer = button
    if b.hard ~= nil then
        outer = HardShadow(s, button, b.hard)
    end
    if card.firstButton == nil then
        card.firstButton = button
    end
    return outer, label
end

--- A toggle row: caption on the left, the control on the right. Every look of the control is its
--- own shape in exact colours; a click shows one and hides the others.
local function MakeToggle(card, s, parent, caption, on, disabled)
    local t = s.toggle
    local p = s.p
    local row = New("HorizontalBox")
    HAdd(row, BodyText(s, caption), { fill = 1 })

    local state = { on = on }
    local paint
    local control

    if t.variant == "check" then
        local radius = t.radius or 3
        local stack = New("Overlay")
        local edgeWidth = t.checkEdgeWidth or 2
        local off = Box(s.name, { fill = t.checkOff, outline = t.checkEdge, width = edgeWidth, radius = radius }, 0)
        local onBox = Box(s.name, { fill = t.checkOn, outline = t.checkEdgeOn, width = edgeWidth, radius = radius }, 0)
        OAdd(stack, off)
        OAdd(stack, onBox)
        local markBox = Image(s.name, Texture("check"), 14, t.checkMark)
        OAdd(stack, markBox, 0, H_CENTER, V_CENTER)
        if t.checkBevel ~= nil then
            stack = Bevel(s.name, stack, t.checkBevel, true)
        end
        paint = function()
            SetShown(off, not state.on)
            SetShown(onBox, state.on)
            SetShown(markBox, state.on)
        end
        control = Sized(stack, 20, 20)
    elseif t.variant == "text" then
        local radius = t.radius or 3
        local stack = New("Overlay")
        local off = Box(s.name, { fill = p.track, radius = radius }, 0)
        local onBox = Box(s.name, { fill = p.accent, radius = radius }, 0)
        OAdd(stack, off)
        OAdd(stack, onBox)
        local word = BodyText(s, "On", p.accentText, s.body.size - 1, { justify = 1, shadow = false })
        OAdd(stack, word, { 6, 2, 6, 2 }, H_CENTER, V_CENTER)
        paint = function()
            SetShown(off, not state.on)
            SetShown(onBox, state.on)
            SetLabel(word, Caption(s, state.on and "On" or "Off"))
            SetTextColor(word, state.on and p.accentText or p.muted)
        end
        control = Sized(stack, 48, 22)
    else
        local square = t.variant == "square"
        local knobSize = t.h - 6
        local stack = New("Overlay")
        local trackR = square and 3 or 1
        local knobR = square and 2 or 1
        -- An off track with offEdge set is an outline only, as in Windows 11.
        local offTrack = Box(s.name, {
            fill = t.offEdge and Alpha(t.offEdge, 0) or t.trackOff,
            outline = t.offEdge,
            width = t.offEdge and 1 or 0,
            radius = trackR,
            pill = not square,
        }, 0)
        local onTrack = Box(s.name, { fill = t.trackOn, radius = trackR, pill = not square }, 0)
        local offKnob = Sized(Box(s.name, { fill = t.knobOff, radius = knobR, pill = not square }, 0), knobSize, knobSize)
        local onKnob = Sized(Box(s.name, { fill = t.knobOn, radius = knobR, pill = not square }, 0), knobSize, knobSize)
        OAdd(stack, offTrack)
        OAdd(stack, onTrack)
        OAdd(stack, offKnob, 3, H_LEFT, V_CENTER)
        OAdd(stack, onKnob, 3, H_RIGHT, V_CENTER)
        paint = function()
            SetShown(offTrack, not state.on)
            SetShown(offKnob, not state.on)
            SetShown(onTrack, state.on)
            SetShown(onKnob, state.on)
        end
        control = Sized(stack, t.w, t.h)
    end
    paint()
    HAdd(row, control, { halign = H_RIGHT })

    local onClick = nil
    if not disabled then
        onClick = function()
            state.on = not state.on
            paint()
            Say(s.name .. " toggle '" .. caption .. "' -> " .. tostring(state.on))
        end
    end
    local button = Button(s.name, WashStates(p.text, s.button.radius, s.button.pill), nil, onClick)
    SetContentAligned(button, row, H_FILL, V_CENTER, { 6, 4, 6, 4 })
    if disabled then
        pcall(function()
            button:SetRenderOpacity(0.45)
        end)
    end
    VAdd(parent, button, { 0, 1, 0, 1 })
end

local function MakeSlider(card, s, parent, caption)
    local sl = s.slider
    local head = New("HorizontalBox")
    HAdd(head, BodyText(s, caption or "Run speed"), { fill = 1, pad = { 6, 0, 0, 0 } })
    local readout = Text(s.name, "62%", Merge(s.data, { shadow = s.textShadow }))
    card.readout = readout
    HAdd(head, readout, { pad = { 0, 0, 6, 0 } })
    VAdd(parent, head, { 0, 6, 0, 0 })

    local slider = New("Slider")
    Try(s.name, "slider style fields", function()
        local st = slider.WidgetStyle
        local bar = { fill = sl.track, radius = sl.thickness / 2 }
        PaintBrush(st.NormalBarImage, bar)
        PaintBrush(st.HoveredBarImage, bar)
        PaintBrush(st.DisabledBarImage, bar)
        local size, radius, pill = { sl.size, sl.size }, 0, false
        if sl.thumb == "round" then
            radius, pill = 1, true
        elseif sl.thumb == "square" then
            radius = 2
        elseif sl.thumb == "bar" then
            size, radius = { 6, sl.size + 4 }, 2
        end
        local thumb = { fill = sl.thumbFill, radius = radius, pill = pill, size = size, outline = sl.thumbEdge,
            width = sl.thumbWidth or 2 }
        PaintBrush(st.NormalThumbImage, thumb)
        PaintBrush(st.HoveredThumbImage, Merge(thumb, { fill = sl.thumbHover }))
        PaintBrush(st.DisabledThumbImage, thumb)
        st.BarThickness = sl.thickness
    end)
    pcall(function()
        slider:SetValue(0.62)
    end)
    card.slider = slider
    card.lastValue = 0.62
    VAdd(parent, Sized(slider, nil, 26), { 6, 0, 6, 4 })
end

--- Put a progress bar in its trough frame when the style has one: an edge, a fill and padding,
--- and a sunken bevel for Windows Classic.
local function FrameProgress(s, widget)
    local f = s.progress.frame
    if f == nil then
        return widget
    end
    local frame = Box(s.name, { fill = f.fill or WHITE, outline = f.edge, width = f.edge and 1 or 0, radius = f.radius or 0 },
        f.pad or 2)
    frame:SetContent(widget)
    if f.bevel ~= nil then
        return Bevel(s.name, frame, f.bevel, true)
    end
    return frame
end

local function MakeProgress(card, s, parent, caption)
    local pr = s.progress
    VAdd(parent, BodyText(s, caption or "Storm intensity"), { 6, 4, 0, 4 })
    if pr.variant == "segments" then
        local row = New("HorizontalBox")
        local segs = {}
        for i = 1, pr.segments do
            local color = pr.fill
            if pr.ramp ~= nil then
                local index
                if pr.cycle then
                    index = (i - 1) % #pr.ramp + 1
                else
                    index = math.min(#pr.ramp, math.floor((i - 1) / pr.segments * #pr.ramp) + 1)
                end
                color = pr.ramp[index]
            end
            local cell = New("Overlay")
            OAdd(cell, Box(s.name, { fill = pr.track, radius = pr.radius }, 0))
            local lit
            if pr.block ~= nil then
                -- A block with its own vertical shading, as in Windows XP.
                lit = Gradient(s.name, pr.block, 6, pr.radius)
            else
                lit = Box(s.name, { fill = color, radius = pr.radius }, 0)
            end
            OAdd(cell, lit)
            segs[i] = lit
            HAdd(row, cell, { fill = 1, pad = { i == 1 and 0 or pr.gap, 0, 0, 0 }, valign = V_FILL })
        end
        card.segments = segs
        card.litCount = -1
        VAdd(parent, FrameProgress(s, Sized(row, nil, pr.height)), { 6, 0, 6, 4 })
        return
    end

    local progress = New("ProgressBar")
    Try(s.name, "progress style fields", function()
        local st = progress.WidgetStyle
        PaintBrush(st.BackgroundImage, { fill = pr.track, radius = pr.radius })
        PaintBrush(st.FillImage, { fill = pr.fill, radius = pr.radius })
        PaintBrush(st.MarqueeImage, { fill = pr.fill, radius = pr.radius })
    end)
    pcall(function()
        progress:SetFillColorAndOpacity(WHITE)
        progress:SetPercent(0.5)
    end)
    card.progress = progress
    VAdd(parent, FrameProgress(s, Sized(progress, nil, pr.height)), { 6, 0, 6, 4 })
end

--- One-of-several picker, used for the Clear, Rain and Tornado choice and for tab bars.
--- variant: "joined" (fills inside one frame), "chips" (separate shapes) or "tabs" (underline).
local function MakeChoice(card, s, parent, labels, selected, cfg, pad)
    local p = s.p
    local row = New("HorizontalBox")
    local items = {}
    local paint

    for i, caption in ipairs(labels) do
        local text = BodyText(s, caption, p.text, s.body.size - 1, { justify = 1 })
        local item = { text = text }
        local content = New("Overlay")
        if cfg.variant == "tabs" then
            local stack = New("VerticalBox")
            VAdd(stack, text, { 0, 4, 0, 4 }, H_CENTER)
            if cfg.markWidth ~= nil then
                -- A short rounded indicator under the selected tab, as in Windows 11.
                item.mark = Box(s.name, { fill = cfg.markFill, radius = 1, pill = true }, 0)
                VAdd(stack, Sized(item.mark, cfg.markWidth, cfg.markHeight or 3), 0, H_CENTER)
            else
                item.mark = Box(s.name, { fill = cfg.markFill }, 0)
                VAdd(stack, Sized(item.mark, nil, 2), 0, H_FILL)
            end
            OAdd(content, stack)
        elseif cfg.variant == "radio" then
            -- Radio buttons: a ring with a dot for the selected one, and the caption beside it.
            local ring = New("Overlay")
            OAdd(ring, Box(s.name, { fill = cfg.radioFill or WHITE, outline = cfg.radioEdge or p.text, width = 1,
                radius = 1, pill = true }, 0))
            item.mark = Sized(Box(s.name, { fill = cfg.markFill, radius = 1, pill = true }, 0), 6, 6)
            OAdd(ring, item.mark, 0, H_CENTER, V_CENTER)
            local line = New("HorizontalBox")
            HAdd(line, Sized(ring, 14, 14), { pad = { 0, 0, 6, 0 } })
            HAdd(line, text)
            OAdd(content, line, { 2, 4, 2, 4 }, H_LEFT, V_CENTER)
        else
            if cfg.variant == "chips" then
                OAdd(content, Box(s.name, { fill = Alpha(p.text, 0), outline = cfg.edge or p.line, width = 1,
                    radius = cfg.radius, pill = cfg.pill }, 0))
            end
            item.mark = Box(s.name, { fill = cfg.markFill, outline = cfg.markEdge, width = cfg.markEdge and 1 or 0,
                radius = cfg.radius, pill = cfg.pill }, 0)
            OAdd(content, item.mark)
            OAdd(content, text, { 8, 5, 8, 5 }, H_CENTER, V_CENTER)
        end
        local button = Button(s.name, WashStates(p.text, cfg.radius, cfg.pill), content, function()
            paint(i)
            Say(s.name .. " choice -> " .. caption)
        end)
        items[i] = item
        local gap = cfg.variant == "chips" and 6 or 2
        HAdd(row, button, { fill = 1, pad = { i == 1 and 0 or gap, 0, 0, 0 }, valign = V_FILL })
    end

    paint = function(index)
        for i, item in ipairs(items) do
            local on = i == index
            SetShown(item.mark, on)
            local color = on and cfg.markText or p.text
            if cfg.variant == "tabs" then
                color = on and (cfg.tabText or cfg.markFill) or p.muted
            elseif cfg.variant == "radio" then
                color = p.text
            end
            SetTextColor(item.text, color)
        end
    end
    paint(selected)

    if cfg.variant == "joined" then
        local ghost = s.button.variant == "ghost"
        local edge = cfg.edge or (ghost and Alpha(p.accent, 0.6) or nil)
        local frame = Box(s.name, {
            fill = cfg.trackFill or (ghost and Alpha(p.accent, 0) or p.surface),
            outline = edge,
            width = edge and 1 or 0,
            radius = (cfg.radius > 0 and not cfg.pill) and cfg.radius + 3 or cfg.radius,
            pill = cfg.pill,
        }, 3)
        SetContentAligned(frame, row, H_FILL, V_FILL, 3)
        VAdd(parent, frame, pad or { 0, 6, 0, 4 })
    else
        VAdd(parent, row, pad or { 0, 6, 0, 4 })
    end
end

local function MakeSection(s, parent, caption)
    local p = s.p
    local label = BodyText(s, caption, s.section.color, s.body.size - 1, { typeface = s.title.typeface })
    if s.section.variant == "rule" then
        local row = New("HorizontalBox")
        HAdd(row, label, { pad = { 0, 0, 10, 0 } })
        HAdd(row, Sized(Box(s.name, { fill = p.line }, 0), nil, 1), { fill = 1 })
        VAdd(parent, row, { 6, 0, 0, 6 })
    else
        VAdd(parent, label, { 6, 0, 0, 6 })
    end
end

--- A single-line text field: an EditableText inside a Border painted as the theme's field.
local function MakeField(card, s, parent, hint)
    local p = s.p
    local f = s.field
    local frame = Box(s.name, { fill = f.fill, outline = f.outline, width = 1, radius = f.radius, pill = f.pill }, 0)
    local edit = New("EditableText")
    Try(s.name, "text field style", function()
        local st = edit.WidgetStyle
        local font = PickFont(s.body.font)
        if font ~= nil then
            st.Font.FontObject = font
        end
        if s.body.typeface ~= nil then
            st.Font.TypefaceFontName = FName(s.body.typeface)
        end
        st.Font.Size = s.body.size
        st.ColorAndOpacity.SpecifiedColor = p.text
        st.ColorAndOpacity.ColorUseRule = 0
        PaintBrush(st.CaretImage, { fill = p.accent })
        PaintBrush(st.BackgroundImageSelected, { fill = Alpha(p.accent, 0.35) })
    end)
    pcall(function()
        edit:SetHintText(FText(hint))
    end)
    SetContentAligned(frame, edit, H_FILL, V_CENTER, { 10, 6, 10, 6 })
    local widget = frame
    if f.bevel ~= nil then
        widget = Bevel(s.name, frame, f.bevel, true)
    end
    VAdd(parent, Sized(widget, nil, 34), { 0, 2, 0, 6 })
end

--- A dropdown: a field-style header with a chevron, and an option list that opens under it.
local function MakeDropdown(card, s, parent, caption, options)
    local p = s.p
    local f = s.field
    local state = { open = false, value = options[1] }
    local header = Box(s.name, { fill = f.fill, outline = f.outline, width = 1, radius = f.radius, pill = f.pill }, 0)
    local row = New("HorizontalBox")
    local valueText = BodyText(s, caption .. ": " .. state.value, p.text)
    HAdd(row, valueText, { fill = 1 })
    local chevronBox, chevron = Image(s.name, Texture("arrow"), 14, p.muted)
    pcall(function()
        chevron:SetRenderTransformAngle(-90)
    end)
    HAdd(row, chevronBox)
    SetContentAligned(header, row, H_FILL, V_CENTER, { 10, 6, 10, 6 })

    local list = New("VerticalBox")
    local listFrame = Box(s.name, { fill = Mix(p.bg, p.text, 0.04), outline = f.outline, width = 1, radius = f.radius }, 4)
    listFrame:SetContent(list)
    pcall(function()
        listFrame:SetVisibility(VIS_COLLAPSED)
    end)

    local function SetOpen(open)
        state.open = open
        pcall(function()
            listFrame:SetVisibility(open and VIS_VISIBLE or VIS_COLLAPSED)
            chevron:SetRenderTransformAngle(open and 90 or -90)
        end)
    end

    for _, option in ipairs(options) do
        local optionText = BodyText(s, option, p.text)
        local optionButton = Button(s.name, WashStates(p.text, f.radius, f.pill), nil, function()
            state.value = option
            SetLabel(valueText, Caption(s, caption .. ": " .. option))
            SetOpen(false)
            Say(s.name .. " dropdown -> " .. option)
        end)
        SetContentAligned(optionButton, optionText, H_FILL, V_CENTER, { 8, 5, 8, 5 })
        VAdd(list, optionButton)
    end

    local headerButton = Button(s.name, WashStates(p.text, f.radius, f.pill), header, function()
        SetOpen(not state.open)
    end)
    VAdd(parent, Sized(headerButton, nil, 34), { 0, 2, 0, 2 })
    VAdd(parent, listFrame, { 0, 2, 0, 6 })
end

local function MakeKeybind(card, s, parent, caption, key)
    local p = s.p
    local row = New("HorizontalBox")
    HAdd(row, BodyText(s, caption), { fill = 1 })
    local chip = Box(s.name, { fill = p.surface, outline = p.line, width = 1, radius = math.min(6, s.button.radius) }, 0)
    local keyText = Text(s.name, key, Merge(s.body, { typeface = s.title.typeface, color = p.text, shadow = s.textShadow,
        justify = 1 }))
    SetContentAligned(chip, keyText, H_CENTER, V_CENTER, { 10, 3, 10, 3 })
    HAdd(row, chip, { halign = H_RIGHT })
    local waiting = false
    local button = Button(s.name, WashStates(p.text, s.button.radius, s.button.pill), nil, function()
        waiting = not waiting
        SetLabel(keyText, waiting and Caption(s, "Press a key") or key)
        SetTextColor(keyText, waiting and p.accent or p.text)
    end)
    SetContentAligned(button, row, H_FILL, V_CENTER, { 6, 4, 6, 4 })
    VAdd(parent, button, { 0, 1, 0, 1 })
end

local function MakeStepper(card, s, parent, caption, value)
    local p = s.p
    local row = New("HorizontalBox")
    HAdd(row, BodyText(s, caption), { fill = 1, pad = { 6, 0, 0, 0 } })
    local valueText
    local function Change(delta)
        return function()
            value = math.max(0, math.min(9, value + delta))
            SetLabel(valueText, tostring(value))
        end
    end
    local minus = MakeButton(card, s, "secondary", "-", Change(-1))
    valueText = Text(s.name, tostring(value), Merge(s.data, { size = s.body.size + 4, shadow = s.textShadow, justify = 1 }))
    local plus = MakeButton(card, s, "secondary", "+", Change(1))
    HAdd(row, Sized(minus, 34, 30))
    HAdd(row, Sized(valueText, 36, nil), { valign = V_CENTER })
    HAdd(row, Sized(plus, 34, 30))
    VAdd(parent, row, { 0, 4, 0, 6 })
end

local function MakeList(card, s, parent, rows)
    local p = s.p
    local marks = {}
    for i, def in ipairs(rows) do
        local content = New("Overlay")
        local mark = Box(s.name, { fill = Alpha(p.accent, 0.16), radius = s.button.radius, pill = s.button.pill }, 0)
        OAdd(content, mark)
        marks[i] = mark
        local row = New("HorizontalBox")
        local color = def.locked and p.muted or p.text
        HAdd(row, (Image(s.name, Texture(def.icon), 16, def.locked and p.muted or s.icons.tint)), { pad = { 0, 0, 10, 0 } })
        HAdd(row, BodyText(s, def.name, color), { fill = 1 })
        HAdd(row, BodyText(s, def.value, def.locked and p.muted or s.icons.alt, s.body.size - 1))
        OAdd(content, row, { 8, 5, 8, 5 })
        local onClick = nil
        if not def.locked then
            onClick = function()
                for k, other in ipairs(marks) do
                    SetShown(other, k == i)
                end
                Say(s.name .. " list -> " .. def.name)
            end
        end
        local button = Button(s.name, WashStates(p.text, s.button.radius, s.button.pill), content, onClick)
        if def.locked then
            pcall(function()
                button:SetRenderOpacity(0.6)
            end)
        end
        VAdd(parent, button, { 0, 1, 0, 1 })
    end
    for k, mark in ipairs(marks) do
        SetShown(mark, k == 1)
    end
end

local function TitleText(card, s, color)
    local spec = Merge(s.title, { shadow = s.title.shadow or s.textShadow })
    if color ~= nil then
        spec.color = color
    end
    local title = Text(s.name, Caption(s, s.name), spec)
    card.title = title
    if not s.motion.glitch then
        return title
    end
    -- Glitch: two coloured copies behind the title, shown for a moment, offset left and right.
    local stack = New("Overlay")
    local ghostA = Text(s.name, Caption(s, s.name), Merge(spec, { color = Alpha(s.p.danger, 0.8), shadow = false }))
    local ghostB = Text(s.name, Caption(s, s.name), Merge(spec, { color = Alpha(s.p.accent, 0.8), shadow = false }))
    OAdd(stack, ghostA, { 3, 0, 0, 0 }, H_LEFT, V_TOP)
    OAdd(stack, ghostB, { 0, 0, 3, 0 }, H_LEFT, V_TOP)
    OAdd(stack, title, 0, H_LEFT, V_TOP)
    SetShown(ghostA, false)
    SetShown(ghostB, false)
    card.ghosts = { ghostA, ghostB }
    return stack
end

local function Titles(card, s, color, subColor)
    local titles = New("VerticalBox")
    VAdd(titles, TitleText(card, s, color))
    VAdd(titles, BodyText(s, s.subtitle, subColor or s.p.muted, s.body.size - 2))
    return titles
end

local function CloseButton(card, s, tint)
    local box = Image(s.name, Texture("close"), 14, tint or s.p.muted)
    local content = New("Overlay")
    OAdd(content, box, 0, H_CENTER, V_CENTER)
    return Sized(Button(s.name, WashStates(tint or s.p.text, s.button.radius, s.button.pill), content, function()
        Pop(card)
        Say(s.name .. " close clicked")
    end), 30, 30)
end

--- Minimise, maximise and close buttons in an operating system's style: "win11", "xp" or "classic".
--- The glyphs are drawn from shapes, and the close cross is the game's close icon.
local function WindowControls(card, s, style)
    local name = s.name
    local panel = s.panel
    local row = New("HorizontalBox")
    local glyphColor = s.p.text
    if style == "xp" then
        glyphColor = WHITE
    elseif style == "classic" then
        glyphColor = panel.controlGlyph or BLACK
    end

    local function Glyph(kind, color, size)
        if kind == "min" then
            return Sized(Box(name, { fill = color }, 0), size, style == "classic" and 2 or 1)
        elseif kind == "max" then
            return Sized(Box(name, { fill = Alpha(color, 0), outline = color, width = 1 }, 0), size, size)
        end
        return (Image(name, Texture("close"), size, color))
    end

    local function Control(kind, index)
        local last = kind == "close"
        local content = New("Overlay")
        local states, watch, size
        local none = { fill = Alpha(WHITE, 0) }
        if style == "win11" then
            -- Full-height 46x32 buttons flush with the top edge. Close turns red with a white
            -- cross, and its hover follows the window's top-right corner.
            local hoverFill = last and Hex("#C42B1C") or Alpha(s.p.text, 0.06)
            local pressFill = last and Hex("#C42B1C", 0.9) or Alpha(s.p.text, 0.04)
            local radius = last and { 0, panel.radius, 0, 0 } or 0
            states = {
                normal = { fill = Alpha(hoverFill, 0), radius = radius },
                hovered = { fill = hoverFill, radius = radius },
                pressed = { fill = pressFill, radius = radius },
            }
            local glyph = Glyph(kind, glyphColor, 10)
            OAdd(content, glyph, 0, H_CENTER, V_CENTER)
            if last then
                local white = Glyph(kind, WHITE, 10)
                OAdd(content, white, 0, H_CENTER, V_CENTER)
                SetShown(white, false)
                watch = function(hovered)
                    SetShown(white, hovered)
                    SetShown(glyph, not hovered)
                end
            end
            size = { 46, 32 }
        elseif style == "xp" then
            -- Rounded 21x21 buttons with a white edge and a glossy gradient: lighter on hover,
            -- darker while pressed. Close is red.
            local stops = last and panel.closeStops or panel.controlStops
            local function Shade(towards, amount)
                local out = {}
                for i, c in ipairs(stops) do
                    out[i] = Mix(c, towards, amount)
                end
                return out
            end
            local normal = Gradient(name, stops, 10, 3)
            local lit = Gradient(name, Shade(WHITE, 0.25), 10, 3)
            local dark = Gradient(name, Shade(BLACK, 0.2), 10, 3)
            OAdd(content, normal, 1)
            OAdd(content, lit, 1)
            OAdd(content, dark, 1)
            SetShown(lit, false)
            SetShown(dark, false)
            -- The bubble: a soft white highlight in the top-left, under the white outline.
            local shine = Sized(Box(name, { fill = Alpha(WHITE, 0.42), radius = 1, pill = true }, 0), 11, 5)
            OAdd(content, shine, { 3, 2, 0, 0 }, H_LEFT, V_TOP)
            OAdd(content, Box(name, { fill = Alpha(WHITE, 0), outline = WHITE, width = 1, radius = 3 }, 0))
            -- Thick white symbols: a short bar low on the left, a box with a heavy top edge, a cross.
            if kind == "min" then
                OAdd(content, Sized(Box(name, { fill = WHITE }, 0), 7, 3), { 5, 0, 0, 5 }, H_LEFT, V_BOTTOM)
            elseif kind == "max" then
                local box = New("Overlay")
                OAdd(box, Sized(Box(name, { fill = Alpha(WHITE, 0), outline = WHITE, width = 1 }, 0), 10, 10))
                OAdd(box, Sized(Box(name, { fill = WHITE }, 0), 10, 3), 0, H_FILL, V_TOP)
                OAdd(content, Sized(box, 10, 10), 0, H_CENTER, V_CENTER)
            else
                OAdd(content, (Image(name, Texture("close"), 12, WHITE)), 0, H_CENTER, V_CENTER)
            end
            states = { normal = none, hovered = none, pressed = none }
            watch = function(hovered, pressed)
                SetShown(normal, not hovered)
                SetShown(lit, hovered and not pressed)
                SetShown(dark, pressed)
            end
            size = { 21, 21 }
        else
            -- Windows Classic: small raised bevel buttons that sink while pressed.
            OAdd(content, Box(name, { fill = panel.controlFace or Hex("#C0C0C0") }, 0))
            local raised = BevelLines(name, content, panel.bevel, false)
            local sunken = BevelLines(name, content, panel.bevel, true)
            for _, line in ipairs(sunken) do
                SetShown(line, false)
            end
            local glyph = Glyph(kind, glyphColor, last and 9 or 7)
            OAdd(content, glyph, 0, H_CENTER, V_CENTER)
            states = { normal = none, hovered = none, pressed = none }
            watch = function(_, pressed)
                for _, line in ipairs(raised) do
                    SetShown(line, not pressed)
                end
                for _, line in ipairs(sunken) do
                    SetShown(line, pressed)
                end
                pcall(function()
                    glyph:SetRenderTranslation({ X = pressed and 1 or 0, Y = pressed and 1 or 0 })
                end)
            end
            size = { 16, 14 }
        end
        local button = Button(name, states, content, function()
            Pop(card)
            Say(name .. " window control " .. kind .. " clicked")
        end)
        if watch ~= nil then
            WatchHover(button, watch)
        end
        local gap = 0
        if style == "xp" and index > 1 then
            gap = 2
        elseif style == "classic" and last then
            gap = 2
        end
        HAdd(row, Sized(button, size[1], size[2]), { pad = { gap, 0, 0, 0 }, valign = V_TOP })
    end

    Control("min", 1)
    Control("max", 2)
    Control("close", 3)
    return row
end

--- macOS window buttons: red, yellow and green circles. Hovering any of them shows the symbol in
--- all three, as macOS does.
local function TrafficLights(card, s)
    local name = s.name
    local row = New("HorizontalBox")
    local glyphs, hovered = {}, {}
    local lights = {
        { "#FF5F57", "#4D0000", "close" },
        { "#FEBC2E", "#995700", "min" },
        { "#28C840", "#006500", "max" },
    }
    for i, def in ipairs(lights) do
        local fill, ink, kind = Hex(def[1]), Hex(def[2]), def[3]
        local content = New("Overlay")
        OAdd(content, Box(name, { fill = fill, outline = Mix(fill, BLACK, 0.15), width = 1, radius = 1, pill = true }, 0))
        local glyph
        if kind == "close" then
            glyph = (Image(name, Texture("close"), 8, ink))
        elseif kind == "min" then
            glyph = Sized(Box(name, { fill = ink }, 0), 6, 1.5)
        else
            glyph = New("Overlay")
            OAdd(glyph, Sized(Box(name, { fill = ink }, 0), 6, 1.5), 0, H_CENTER, V_CENTER)
            OAdd(glyph, Sized(Box(name, { fill = ink }, 0), 1.5, 6), 0, H_CENTER, V_CENTER)
        end
        OAdd(content, glyph, 0, H_CENTER, V_CENTER)
        SetShown(glyph, false)
        glyphs[i] = glyph
        local states = {
            normal = { fill = Alpha(BLACK, 0), radius = 1, pill = true },
            hovered = { fill = Alpha(BLACK, 0), radius = 1, pill = true },
            pressed = { fill = Alpha(BLACK, 0.18), radius = 1, pill = true },
        }
        local button = Button(name, states, content, function()
            Pop(card)
            Say(name .. " traffic light " .. kind .. " clicked")
        end)
        WatchHover(button, function(isHovered)
            hovered[i] = isHovered
            local any = hovered[1] or hovered[2] or hovered[3]
            for _, g in ipairs(glyphs) do
                SetShown(g, any == true)
            end
        end)
        HAdd(row, Sized(button, 12, 12), { pad = { i == 1 and 0 or 8, 0, 0, 0 } })
    end
    return row
end

--- The header inside the content column. "bar", "xpbar" and "classic" headers are drawn by the panel.
local function MakeHeader(card, s, column)
    local panel = s.panel
    local p = s.p
    if panel.header == "bar" then
        return
    end
    if panel.header == "xpbar" or panel.header == "classic" then
        VAdd(column, BodyText(s, s.subtitle, p.muted, s.body.size - 1), { 6, 0, 0, 10 })
        return
    end
    if panel.header == "window" then
        -- Windows 11: the title bar is drawn by the panel; the page heading starts the content.
        local heading = Text(s.name, s.subtitle, Merge(s.title, { shadow = s.textShadow }))
        card.title = heading
        VAdd(column, heading, { 6, 0, 0, 12 })
        return
    end
    if panel.header == "mac" then
        -- macOS: traffic lights on the left and the title centred over the whole bar.
        local bar = New("Overlay")
        OAdd(bar, TrafficLights(card, s), { 2, 0, 0, 0 }, H_LEFT, V_CENTER)
        local title = Text(s.name, s.name, Merge(s.title, { shadow = s.textShadow }))
        card.title = title
        OAdd(bar, title, 0, H_CENTER, V_CENTER)
        VAdd(column, Sized(bar, nil, 24), { 0, -4, 0, 8 })
        VAdd(column, BodyText(s, s.subtitle, p.muted, s.body.size - 1, { justify = 1 }), { 0, 0, 0, 10 }, H_CENTER)
        VAdd(column, Sized(Box(s.name, { fill = p.line }, 0), nil, 1), { 0, 0, 0, 10 })
        return
    end
    if panel.header == "rule" then
        VAdd(column, TitleText(card, s), { 0, 0, 0, 6 })
        VAdd(column, Sized(Box(s.name, { fill = p.accent }, 0), 56, 6), { 0, 0, 0, 6 }, H_LEFT)
        VAdd(column, BodyText(s, s.subtitle, p.muted, s.body.size - 2), { 0, 0, 0, 12 })
        return
    end
    local header = New("HorizontalBox")
    if panel.header == "badge" then
        local iconBox = Image(s.name, Texture(s.icon), 20, p.accent)
        local badge = Box(s.name, { fill = Mix(p.bg, p.accent, 0.16), radius = math.min(8, panel.radius) }, 0)
        SetContentAligned(badge, iconBox, H_CENTER, V_CENTER, 7)
        HAdd(header, Sized(badge, 36, 36), { pad = { 0, 0, 12, 0 } })
    end
    HAdd(header, Titles(card, s), { fill = 1 })
    if card.deep then
        HAdd(header, CloseButton(card, s), { valign = V_TOP })
    end
    VAdd(column, header, { 0, 0, 0, 10 })
    VAdd(column, Sized(Box(s.name, { fill = p.line }, 0), nil, 1), { 0, 0, 0, 10 })
end

--- A band drawn edge to edge across the top of the panel: a header bar, a hazard strip or an accent strip.
local function MakeTopBand(card, s)
    local panel = s.panel
    local p = s.p
    local r = panel.radius
    local top = { r, r, 0, 0 }
    if panel.header == "bar" then
        local bar = Box(s.name, { fill = p.accent, radius = top }, { panel.pad, 12, panel.pad - 6, 12 })
        local row = New("HorizontalBox")
        HAdd(row, Titles(card, s, p.accentText, Alpha(p.accentText, 0.8)), { valign = V_TOP })
        if s.motion.cursor then
            card.cursor = Box(s.name, { fill = p.accentText }, 0)
            HAdd(row, Sized(card.cursor, 10, 20), { pad = { 8, 2, 0, 0 }, valign = V_TOP })
        end
        HAdd(row, New("Spacer"), { fill = 1 })
        if card.deep then
            HAdd(row, CloseButton(card, s, p.accentText), { valign = V_TOP })
        end
        bar:SetContent(row)
        return bar
    elseif panel.header == "window" then
        -- Windows 11: a 32-high title bar flush with the window's top edge: a monochrome app icon,
        -- the app name, and full-height caption buttons in the top-right corner.
        local row = New("HorizontalBox")
        HAdd(row, (Image(s.name, Texture(s.icon), 14, p.text)), { pad = { 14, 0, 10, 0 } })
        HAdd(row, BodyText(s, s.name, p.text, s.body.size - 2), { fill = 1 })
        HAdd(row, WindowControls(card, s, "win11"), { valign = V_TOP })
        return Sized(row, nil, 32)
    elseif panel.header == "xpbar" or panel.header == "classic" then
        -- A window title bar: Windows XP's glossy blue gradient, top to bottom, or Windows
        -- Classic's navy-to-blue gradient, left to right.
        local xp = panel.header == "xpbar"
        local bar = New("Overlay")
        OAdd(bar, Gradient(s.name, panel.barStops, xp and 14 or 24, xp and math.max(0, r - 3) or 0, not xp, "first"))
        local row = New("HorizontalBox")
        local title = Text(s.name, s.name, Merge(s.title, {
            color = WHITE,
            shadow = xp and { x = 1, y = 1, color = panel.titleShadow or Hex("#0F1089") } or false,
        }))
        card.title = title
        HAdd(row, title, { fill = 1 })
        HAdd(row, WindowControls(card, s, xp and "xp" or "classic"))
        OAdd(bar, row, xp and { 10, 5, 6, 5 } or { 6, 2, 3, 2 }, H_FILL, V_CENTER)
        return Sized(bar, nil, xp and 30 or 20)
    elseif panel.header == "tape" then
        local row = New("HorizontalBox")
        for i = 1, 30 do
            local block = Box(s.name, { fill = (i % 2 == 1) and p.accent or Hex("#000000", 0.85) }, 0)
            HAdd(row, block, { fill = 1, valign = V_FILL })
        end
        return Sized(row, nil, panel.tape or 8)
    elseif panel.strip ~= nil then
        return Sized(Box(s.name, { fill = p.accent, radius = top }, 0), nil, panel.strip)
    end
    return nil
end

local function Bracket(s, halign, valign)
    local p = s.p
    local corner = New("Overlay")
    OAdd(corner, Sized(Box(s.name, { fill = p.accent }, 0), 18, 2), 0, halign, valign)
    OAdd(corner, Sized(Box(s.name, { fill = p.accent }, 0), 2, 18), 0, halign, valign)
    return Sized(corner, 18, 18)
end

local function MakeBlur(name, strength, radius, inset)
    local blur = New("BackgroundBlur")
    Try(name, "background blur", function()
        blur:SetBlurStrength(strength)
        blur:SetApplyAlphaToBlur(true)
        blur:SetPadding(Margin(0))
    end)
    Try(name, "blur corner radius", function()
        blur:SetCornerRadius({ X = radius, Y = radius, Z = radius, W = radius })
    end)
    return blur, inset
end

--- Wrap a content column in the theme's panel and its decorations, and return the card's root.
local function WrapPanel(card, s, column)
    local name = s.name
    local panel = s.panel
    local p = s.p

    -- The column scrolls if a small screen cuts the card short; the scrollbar and its edge shadows are hidden.
    local scroll = New("ScrollBox")
    pcall(function()
        scroll:SetScrollBarVisibility(VIS_COLLAPSED)
    end)
    Try(name, "scroll shadow fields", function()
        local st = scroll.WidgetStyle
        st.TopShadowBrush.DrawAs = DRAW_NONE
        st.BottomShadowBrush.DrawAs = DRAW_NONE
        st.LeftShadowBrush.DrawAs = DRAW_NONE
        st.RightShadowBrush.DrawAs = DRAW_NONE
    end)
    scroll:AddChild(column)

    local stack = New("VerticalBox")
    local band = MakeTopBand(card, s)
    if band ~= nil then
        VAdd(stack, band, panel.bandInset or 0)
    end
    local columnSlot = stack:AddChildToVerticalBox(scroll)
    pcall(function()
        columnSlot:SetPadding(Margin(panel.pad))
        columnSlot:SetSize({ SizeRule = 1, Value = 1 })
    end)
    if panel.statusBar ~= nil then
        -- A status bar along the bottom edge, as on Windows XP forms: a dividing line and a short
        -- status message.
        local sb = panel.statusBar
        VAdd(stack, Sized(Box(name, { fill = sb.line }, 0), nil, 1))
        local status = Box(name, { fill = sb.fill }, { 8, 3, 8, 4 })
        status:SetContent(BodyText(s, sb.text, p.text, s.body.size - 2))
        VAdd(stack, status)
    end

    local panelBox = Box(name, { fill = panel.fill, outline = panel.outline, width = panel.width,
        radius = panel.radii or panel.radius }, 0)
    panelBox:SetContent(stack)

    local body = New("Overlay")
    if panel.blur then
        local blur = MakeBlur(name, panel.blur, panel.blurRadius, panel.blurInset)
        OAdd(body, blur, panel.blurInset)
    end
    if panel.sweep then
        -- A projection sweep: a soft bright band, three strips deep, that travels down the card.
        local sweep = New("VerticalBox")
        VAdd(sweep, Sized(Box(name, { fill = Alpha(p.accent, 0.03) }, 0), nil, 24))
        VAdd(sweep, Sized(Box(name, { fill = Alpha(p.accent, 0.08) }, 0), nil, 10))
        VAdd(sweep, Sized(Box(name, { fill = Alpha(p.accent, 0.03) }, 0), nil, 24))
        pcall(function()
            sweep:SetVisibility(VIS_HIT_TEST_INVISIBLE)
        end)
        card.sweepBand = sweep
    end
    if type(panel.bevel) == "table" then
        OAdd(body, Bevel(name, panelBox, panel.bevel))
    else
        OAdd(body, panelBox)
    end
    if card.sweepBand ~= nil then
        OAdd(body, card.sweepBand, 0, H_FILL, V_TOP)
        -- Interference: a darker band that drifts at a changing speed, and a tear, a bright line
        -- with a dark gap under it, shown only during a glitch.
        local noise = Sized(Box(name, { fill = Alpha(BLACK, 0.22) }, 0), nil, 30)
        SetShown(noise, true)
        OAdd(body, noise, 0, H_FILL, V_TOP)
        card.noiseBand = noise
        local tear = New("VerticalBox")
        VAdd(tear, Sized(Box(name, { fill = Alpha(p.accent, 0.45) }, 0), nil, 2))
        VAdd(tear, Sized(Box(name, { fill = Alpha(BLACK, 0.45) }, 0), nil, 10))
        SetShown(tear, false)
        OAdd(body, tear, 0, H_FILL, V_TOP)
        card.tear = tear
        pcall(function()
            body:SetClipping(CLIP_TO_BOUNDS)
        end)
    end
    if s.motion.sparkle then
        -- Frost glints: small white points that brighten and fade one after another.
        card.sparkles = {}
        local spots = {
            { H_RIGHT, V_TOP, { 0, 12, 28, 0 }, 4 }, { H_RIGHT, V_TOP, { 0, 26, 46, 0 }, 3 },
            { H_RIGHT, V_TOP, { 0, 8, 64, 0 }, 2 }, { H_LEFT, V_BOTTOM, { 22, 0, 0, 18 }, 3 },
            { H_LEFT, V_BOTTOM, { 40, 0, 0, 30 }, 2 }, { H_RIGHT, V_BOTTOM, { 0, 0, 30, 24 }, 3 },
        }
        for i, spot in ipairs(spots) do
            local dot = Sized(Box(name, { fill = WHITE, radius = 1, pill = true }, 0), spot[4], spot[4])
            SetShown(dot, true)
            OAdd(body, dot, spot[3], spot[1], spot[2])
            card.sparkles[i] = dot
        end
    end
    if panel.scanlines then
        -- CRT scanlines, drawn as lines rather than a tiled texture: the game's scanline texture
        -- tiled into broad bands whatever tile size was set. Each period is a dark line and a gap,
        -- every line a slightly different shade, with an occasional faint bright phosphor row.
        local strength = type(panel.scanlines) == "number" and panel.scanlines or 0.25
        local stack = New("VerticalBox")
        local seed = { seed = 4242 + card.index * 131 }
        local period = panel.scanPeriod or 2.5
        local count = math.floor(640 / period)
        for _ = 1, count do
            local r = Rand(seed)
            local color
            if r > 0.93 then
                color = Alpha(p.accent, strength * 0.35)
            else
                color = Alpha(BLACK, strength * (0.55 + 0.9 * Rand(seed)))
            end
            local line = Box(name, { fill = color }, { 0, 0.5, 0, 0.5 })
            VAdd(stack, line, { 0, 0, 0, period - 1 })
        end
        SetShown(stack, true)
        OAdd(body, stack, panel.width + 1, H_FILL, V_TOP)
        card.scanlines = stack
        pcall(function()
            body:SetClipping(CLIP_TO_BOUNDS)
        end)
    end
    if panel.bevel == true or panel.rim ~= nil then
        -- A rim: a light line inside the top edge and a dark line inside the bottom edge, kept clear
        -- of the rounded corners.
        local rim = panel.rim or { light = Alpha(WHITE, 0.7), dark = Alpha(BLACK, 0.25) }
        local inset = math.max(4, panel.radius)
        OAdd(body, Sized(Box(name, { fill = rim.light }, 0), nil, 1), { inset, 1, inset, 0 }, H_FILL, V_TOP)
        OAdd(body, Sized(Box(name, { fill = rim.dark }, 0), nil, 1), { inset, 0, inset, 1 }, H_FILL, V_BOTTOM)
    end
    if panel.corners then
        OAdd(body, Bracket(s, H_LEFT, V_TOP), 0, H_LEFT, V_TOP)
        OAdd(body, Bracket(s, H_RIGHT, V_TOP), 0, H_RIGHT, V_TOP)
        OAdd(body, Bracket(s, H_LEFT, V_BOTTOM), 0, H_LEFT, V_BOTTOM)
        OAdd(body, Bracket(s, H_RIGHT, V_BOTTOM), 0, H_RIGHT, V_BOTTOM)
    end
    card.body = body

    local root = New("Overlay")
    if panel.hard ~= nil then
        root = HardShadow(s, body, panel.hard)
    elseif panel.shadow ~= nil then
        local layers = panel.shadow.layers
        local depth = layers[#layers][2]
        for _, layer in ipairs(layers) do
            local a, d = layer[1], layer[2]
            local dx = math.floor(d * 0.5 + 0.5)
            local shade = Box(name, { fill = Alpha(panel.shadow.color, a), radius = panel.radius + 2 }, 0)
            OAdd(root, shade, { dx, d, depth - dx, depth - d })
        end
        OAdd(root, body, { 0, 0, depth, depth })
    else
        OAdd(root, body)
    end
    return root
end

--- An icon on a rounded square tile with a top-to-bottom gradient and a white glyph, as in macOS
--- System Settings.
local function IconTile(s, iconName, stops, size)
    local tile = New("Overlay")
    OAdd(tile, Gradient(s.name, stops, 6, math.floor(size * 0.24)))
    OAdd(tile, (Image(s.name, Texture(iconName), math.floor(size * 0.6), WHITE)), 0, H_CENTER, V_CENTER)
    return Sized(tile, size, size)
end

local function MakeIconRow(s, column)
    local icons = New("HorizontalBox")
    local iconNames = { "check", "close", "crown", "fuel", "bolt", "map" }
    for i, iconName in ipairs(iconNames) do
        local widget
        if s.icons.tiles ~= nil then
            widget = IconTile(s, iconName, s.icons.tiles[(i - 1) % #s.icons.tiles + 1], 22)
        else
            local tint = i % 2 == 0 and s.icons.alt or s.icons.tint
            widget = (Image(s.name, Texture(iconName), 18, tint))
        end
        HAdd(icons, widget, { pad = { i == 1 and 6 or (s.icons.tiles and 10 or 14), 0, 0, 0 } })
    end
    VAdd(column, icons, { 0, 6, 0, 6 })
end

--- A compact card: the same controls on every style, for comparing styles side by side.
local function BuildCompactCard(index, theme)
    local s = Resolve(theme)
    local name = s.name
    local card = { index = index, s = s }

    local column = New("VerticalBox")
    MakeHeader(card, s, column)

    local buttons = New("HorizontalBox")
    local specs = {
        { role = "primary", caption = "Apply", onClick = function() Pop(card) Say(name .. " Apply clicked") end },
        { role = "secondary", caption = "Reset", onClick = function() Pop(card) Say(name .. " Reset clicked") end },
        { role = "danger", caption = "Clear storms", onClick = function() Shake(card) Say(name .. " Clear storms clicked") end },
    }
    for i, spec in ipairs(specs) do
        local button = MakeButton(card, s, spec.role, spec.caption, spec.onClick)
        HAdd(buttons, button, { fill = i == 3 and 1.4 or 1, pad = { i == 1 and 0 or 8, 0, 0, 0 }, valign = V_FILL })
    end
    VAdd(column, Sized(buttons, nil, s.button.height + (s.button.hard and s.button.hard.d or 0)), { 0, 0, 0, 8 })

    MakeToggle(card, s, column, "Infinite stamina", true)
    MakeToggle(card, s, column, "No fall damage", false)
    MakeSlider(card, s, column)
    MakeProgress(card, s, column)
    MakeChoice(card, s, column, { "Clear", "Rain", "Tornado" }, 2, s.choice)
    MakeIconRow(s, column)
    VAdd(column, BodyText(s, s.footer, s.p.muted, s.body.size - 3, { wrap = true, spacing = 0 }), { 6, 0, 6, 0 })

    card.root = WrapPanel(card, s, column)
    return card
end

--- A full menu: header, tabs, three sections side by side, and an action bar.
local function BuildDeepCard(index, theme)
    local s = Resolve(theme)
    local name = s.name
    local p = s.p
    local card = { index = index, s = s, deep = true }

    local column = New("VerticalBox")
    MakeHeader(card, s, column)
    MakeChoice(card, s, column, { "Player", "World", "Items", "Keys" }, 1, s.tabs, { 0, 0, 0, 12 })

    local sections = New("HorizontalBox")
    local function Section(caption, first)
        local col = New("VerticalBox")
        MakeSection(s, col, caption)
        HAdd(sections, col, { fill = 1, pad = { first and 0 or 20, 0, 0, 0 }, valign = V_TOP })
        return col
    end

    local movement = Section("Movement", true)
    MakeToggle(card, s, movement, "Infinite stamina", true)
    MakeToggle(card, s, movement, "No fall damage", false)
    MakeToggle(card, s, movement, "God mode (host only)", false, true)
    MakeSlider(card, s, movement, "Run speed")
    MakeKeybind(card, s, movement, "Fly", "F")

    local storms = Section("Storms")
    MakeProgress(card, s, storms, "Storm intensity")
    MakeChoice(card, s, storms, { "Clear", "Rain", "Tornado" }, 2, s.choice)
    MakeStepper(card, s, storms, "Tornadoes", 3)
    local clear = MakeButton(card, s, "danger", "Clear all storms", function()
        Shake(card)
        Say(name .. " Clear all storms clicked")
    end)
    VAdd(storms, Sized(clear, nil, s.button.height), { 0, 4, 0, 0 })

    local items = Section("Items")
    MakeField(card, s, items, Caption(s, "Search items"))
    MakeDropdown(card, s, items, "Spawn at", { "Base camp", "Your truck", "Your position" })
    MakeList(card, s, items, {
        { icon = "fuel", name = "Pickup truck", value = "Ready" },
        { icon = "bolt", name = "Weather radio", value = "2 left" },
        { icon = "crown", name = "Storm siren", value = "Locked", locked = true },
    })

    VAdd(column, sections, { 0, 0, 0, 12 })

    -- Action bar: a status line and the two actions.
    VAdd(column, Sized(Box(name, { fill = p.line }, 0), nil, 1), { 0, 0, 0, 10 })
    local bar = New("HorizontalBox")
    HAdd(bar, BodyText(s, "Changes save automatically", p.muted, s.body.size - 1), { fill = 1, pad = { 6, 0, 0, 0 } })
    local reset = MakeButton(card, s, "secondary", "Reset", function()
        Pop(card)
        Say(name .. " Reset clicked")
    end)
    local apply = MakeButton(card, s, "primary", "Apply", function()
        Pop(card)
        Say(name .. " Apply clicked")
    end)
    local hardD = s.button.hard and s.button.hard.d or 0
    HAdd(bar, Sized(reset, 110, s.button.height + hardD), { pad = { 0, 0, 8, 0 } })
    HAdd(bar, Sized(apply, 110, s.button.height + hardD))
    VAdd(column, bar)

    card.root = WrapPanel(card, s, column)
    return card
end

local function ReadBack(card)
    local name = card.s.name
    local parts = {}
    pcall(function()
        local hovered = card.firstButton.WidgetStyle.Hovered
        parts[#parts + 1] = "hovered.DrawAs=" .. tostring(hovered.DrawAs)
        parts[#parts + 1] = "hovered.radius=" .. tostring(hovered.OutlineSettings.CornerRadii.X)
    end)
    pcall(function()
        local f = card.title.Font
        parts[#parts + 1] = "title.size=" .. tostring(f.Size)
        parts[#parts + 1] = "title.typeface=" .. f.TypefaceFontName:ToString()
        parts[#parts + 1] = "title.font=" .. (f.FontObject and f.FontObject:GetFullName() or "nil")
    end)
    if #parts > 0 then
        Say(name .. " read-back: " .. table.concat(parts, " "))
    end
end

------------------------------------------------------------------------------------------
-- Gallery
------------------------------------------------------------------------------------------

local function BuildRoot()
    local outer = UEHelpers.GetGameInstance()
    if not Valid(outer) then
        outer = UEHelpers.GetPlayerController()
    end
    if not Valid(outer) then
        error("no GameInstance or PlayerController to own the gallery")
    end

    for key, path in pairs(FONT_PATHS) do
        local font = FindAsset(path)
        if font ~= nil then
            Say("font " .. key .. " typefaces: " .. TypefaceNames(font))
        end
    end

    local hud = StaticConstructObject(StaticFindObject("/Script/UMG.UserWidget"), outer, FName("StyleLab_Root"))
    if not Valid(hud) then
        error("could not construct the root UserWidget")
    end
    S.root = hud
    local tree = StaticConstructObject(StaticFindObject("/Script/UMG.WidgetTree"), hud, FName("StyleLab_Tree"))
    hud.WidgetTree = tree
    S.tree = tree

    local canvas = New("CanvasPanel")
    tree.RootWidget = canvas
    S.canvas = canvas

    -- Backdrop: dims the game and takes clicks that miss every card.
    local backdrop = Box("Gallery", { fill = { R = 0, G = 0, B = 0, A = 0.35 } }, 0)
    local backSlot = canvas:AddChildToCanvas(backdrop)
    pcall(function()
        backSlot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        backSlot:SetOffsets(Margin(0))
    end)

    -- Banner: every page, the current one in white, and a Close button.
    local bannerRow = New("HorizontalBox")
    for i, page in ipairs(PAGES) do
        local label = Text("Gallery", page.key .. "  " .. page.title, {
            font = "roboto", typeface = "Bold", size = 14, color = Hex("#FFFFFF", 0.5),
        })
        S.bannerLabels[i] = label
        HAdd(bannerRow, label, { pad = { i == 1 and 4 or 20, 0, 0, 0 } })
    end
    local closeLabel = Text("Gallery", "Close", { font = "roboto", typeface = "Bold", size = 14, color = WHITE, justify = 1 })
    local closeContent = New("Overlay")
    OAdd(closeContent, closeLabel, { 14, 4, 14, 4 }, H_CENTER, V_CENTER)
    local closeButton = Button("Gallery", {
        normal = { fill = Hex("#FFFFFF", 0.12), radius = 1, pill = true },
        hovered = { fill = Hex("#FFFFFF", 0.24), radius = 1, pill = true },
        pressed = { fill = Hex("#FFFFFF", 0.36), radius = 1, pill = true },
    }, closeContent, function()
        S.closeRequested = true
    end)
    HAdd(bannerRow, closeButton, { pad = { 24, 0, 0, 0 } })
    local banner = Box("Gallery", { fill = Hex("#101216", 0.88), outline = Hex("#FFFFFF", 0.15), width = 1,
        radius = 1, pill = true }, { 18, 7, 8, 7 })
    banner:SetContent(bannerRow)
    local bannerSlot = canvas:AddChildToCanvas(banner)
    pcall(function()
        bannerSlot:SetAutoSize(true)
        bannerSlot:SetAnchors({ Minimum = { X = 0.5, Y = 0.012 }, Maximum = { X = 0.5, Y = 0.012 } })
        bannerSlot:SetAlignment({ X = 0.5, Y = 0 })
        bannerSlot:SetOffsets(Margin(0))
        bannerSlot:SetZOrder(10)
    end)

    hud:SetVisibility(VIS_COLLAPSED)
    Step("AddToViewport")
    hud:AddToViewport(900)
end

--- Build one page into its own canvas over the gallery.
local function BuildPage(index)
    local def = PAGES[index]
    local page = { index = index, cards = {}, clickables = {}, hovers = {} }
    S.pages[index] = page
    S.buildTarget = page

    local layer = New("CanvasPanel")
    local layerSlot = S.canvas:AddChildToCanvas(layer)
    pcall(function()
        layerSlot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
        layerSlot:SetOffsets(Margin(0))
        layerSlot:SetZOrder(1)
    end)
    page.layer = layer

    local entries, builder
    if def.layout == "deep" then
        entries, builder = def.themes, BuildDeepCard
    else
        entries, builder = def.themes, BuildCompactCard
    end
    local grid = LAYOUTS[def.layout]

    for i, entry in ipairs(entries) do
        local ok, cardOrErr = pcall(builder, i, entry)
        if ok then
            local card = cardOrErr
            page.cards[#page.cards + 1] = card
            local col = (i - 1) % grid.cols
            local row = math.floor((i - 1) / grid.cols)
            local x = grid.x0 + col * grid.dx
            local y = grid.y0 + row * grid.dy
            local slot = layer:AddChildToCanvas(card.root)
            pcall(function()
                slot:SetAutoSize(false)
                slot:SetAnchors({ Minimum = { X = x, Y = y }, Maximum = { X = x + grid.w, Y = y + grid.h } })
                slot:SetOffsets(Margin(0))
                slot:SetAlignment({ X = 0, Y = 0 })
            end)
        else
            Say(tostring(entry.name or entry.label) .. " card raised: " .. tostring(cardOrErr))
        end
    end
    S.buildTarget = nil

    for _, card in ipairs(page.cards) do
        ReadBack(card)
    end
    local summary = {}
    for _, what in ipairs(resultOrder) do
        local r = results[what]
        summary[#summary + 1] = string.format("%s %d ok %d failed", what, r.ok, r.failed)
    end
    Say(string.format("page %s built: %d of %d cards, %d clickable widgets", def.key, #page.cards, #entries,
        #page.clickables))
    Say("build summary so far: " .. table.concat(summary, "; "))
    return page
end

------------------------------------------------------------------------------------------
-- Input
------------------------------------------------------------------------------------------

local function WidgetLibrary()
    return StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
end

local function InputOn()
    local pc = UEHelpers.GetPlayerController()
    if not Valid(pc) then
        return
    end
    if S.savedInput == nil then
        S.savedInput = {
            cursor = pc.bShowMouseCursor == true,
            click = pc.bEnableClickEvents == true,
            hover = pc.bEnableMouseOverEvents == true,
            look = pcall(function()
                pc:SetIgnoreLookInput(true)
            end),
        }
    end
    pc.bShowMouseCursor = true
    pc.bEnableClickEvents = true
    pc.bEnableMouseOverEvents = true
    local lib = WidgetLibrary()
    if not pcall(function()
        lib:SetInputMode_GameAndUIEx(pc, S.root, 0, false, false)
    end) then
        pcall(function()
            lib:SetInputMode_GameAndUIEx(pc, S.root, 0, false)
        end)
    end
end

local function InputOff()
    local pc = UEHelpers.GetPlayerController()
    local saved = S.savedInput
    S.savedInput = nil
    if not Valid(pc) or saved == nil then
        return
    end
    pc.bShowMouseCursor = saved.cursor
    pc.bEnableClickEvents = saved.click
    pc.bEnableMouseOverEvents = saved.hover
    if saved.look then
        pcall(function()
            pc:SetIgnoreLookInput(false)
        end)
    end
    if not saved.cursor then
        local lib = WidgetLibrary()
        if not pcall(function()
            lib:SetInputMode_GameOnly(pc, false)
        end) then
            pcall(function()
                lib:SetInputMode_GameOnly(pc)
            end)
        end
    end
end

local function Close()
    S.open = false
    S.closeRequested = false
    if Valid(S.root) then
        S.root:SetVisibility(VIS_COLLAPSED)
    end
    InputOff()
    Say("closed")
end

local function ShowPage(index)
    if S.open and S.page == index then
        Close()
        return
    end
    if not Valid(S.root) then
        local ok, err = pcall(BuildRoot)
        if not ok then
            Say("gallery build raised: " .. tostring(err))
            return
        end
    end
    local page = S.pages[index]
    if page == nil then
        local ok, result = pcall(BuildPage, index)
        if not ok then
            Say("page " .. PAGES[index].key .. " build raised: " .. tostring(result))
            S.buildTarget = nil
            return
        end
        page = result
    end
    for i, other in pairs(S.pages) do
        pcall(function()
            other.layer:SetVisibility(i == index and VIS_VISIBLE or VIS_COLLAPSED)
        end)
    end
    for i, label in ipairs(S.bannerLabels) do
        SetTextColor(label, i == index and WHITE or Hex("#FFFFFF", 0.5))
    end
    for _, card in ipairs(page.cards) do
        card.settled = false
        pcall(function()
            card.root:SetRenderOpacity(0)
        end)
    end
    S.page = index
    S.openedAt = os.clock()
    S.root:SetVisibility(VIS_VISIBLE)
    if not S.open then
        S.open = true
        InputOn()
    end
    Say("showing page " .. PAGES[index].key .. " " .. PAGES[index].title)
end

------------------------------------------------------------------------------------------
-- Tick: clicks and motion
------------------------------------------------------------------------------------------

local OPEN_STAGGER = 0.06
local OPEN_DURATION = 0.32
local SHAKE_DURATION = 0.4
local POP_DURATION = 0.25

local function ClickIn(list)
    for _, c in ipairs(list) do
        local hovered = false
        pcall(function()
            hovered = c.widget:IsHovered() == true
        end)
        if hovered then
            if c.onClick ~= nil then
                local ok, err = pcall(c.onClick)
                if not ok then
                    Say(c.card .. " click raised: " .. tostring(err))
                end
            end
            return true
        end
    end
    return false
end

local function HandleClick()
    if ClickIn(S.globalClickables) then
        return
    end
    local page = S.pages[S.page]
    if page ~= nil then
        ClickIn(page.clickables)
    end
end

local function AnimateCard(card, now)
    local s = card.s
    local x, y, scale, opacity = 0, 0, 1, 1

    local k = (now - S.openedAt - (card.index - 1) * OPEN_STAGGER) / OPEN_DURATION
    if k < 1 then
        k = math.max(k, 0)
        local e = 1 - (1 - k) ^ 3
        opacity = e
        y = (1 - e) * 24
    end

    if card.shakeAt ~= nil then
        local t = now - card.shakeAt
        if t < SHAKE_DURATION then
            x = math.sin(t * 60) * 7 * (1 - t / SHAKE_DURATION)
        else
            card.shakeAt = nil
        end
    end

    if card.popAt ~= nil then
        local t = now - card.popAt
        if t < POP_DURATION then
            scale = 1 + 0.015 * math.sin(math.pi * t / POP_DURATION)
        else
            card.popAt = nil
        end
    end

    local glitching = false
    if s.motion.glitch then
        local g = card.glitch
        if g == nil then
            g = { seed = 12345 + card.index * 7919, nextAt = now + 1, untilAt = 0, fx = {} }
            card.glitch = g
        end
        if now >= g.nextAt then
            -- Start a glitch: a random length and a random mix of effects, at least one.
            g.untilAt = now + 0.05 + 0.2 * Rand(g)
            g.fx = {
                jitter = Rand(g) < 0.7,
                split = Rand(g) < 0.6,
                flicker = Rand(g) < 0.5,
                tear = Rand(g) < 0.5,
                roll = Rand(g) < 0.3,
            }
            if not (g.fx.jitter or g.fx.split or g.fx.flicker or g.fx.tear or g.fx.roll) then
                g.fx.jitter = true
            end
            g.tearY = 20 + Rand(g) * 380
            g.rollY = (Rand(g) * 2 - 1) * 6
            -- Glitches sometimes come in bursts, a fraction of a second apart.
            local gap = Rand(g) < 0.3 and (0.08 + 0.25 * Rand(g)) or (0.7 + 3.0 * Rand(g))
            g.nextAt = g.untilAt + gap
        end
        glitching = now < g.untilAt
        local fx = glitching and g.fx or {}
        if fx.jitter then
            x = x + (Rand(g) * 2 - 1) * 8
        end
        if fx.roll then
            y = y + g.rollY
        end
        if fx.flicker then
            opacity = opacity * (0.4 + 0.45 * Rand(g))
        end
        if card.ghosts ~= nil then
            local split = fx.split == true
            if split ~= card.wasSplit then
                SetShown(card.ghosts[1], split)
                SetShown(card.ghosts[2], split)
                card.wasSplit = split
            end
            if split then
                local d = 2 + Rand(g) * 5
                card.ghosts[1]:SetRenderTranslation({ X = d, Y = (Rand(g) - 0.5) * 2 })
                card.ghosts[2]:SetRenderTranslation({ X = -d, Y = (Rand(g) - 0.5) * 2 })
            end
        end
        if card.tear ~= nil then
            local tear = fx.tear == true
            if tear ~= card.wasTear then
                SetShown(card.tear, tear)
                card.wasTear = tear
            end
            if tear then
                card.tear:SetRenderTranslation({ X = (Rand(g) * 2 - 1) * 10, Y = g.tearY })
            end
        end
        -- The scanlines never sit quite still: a small random jump now and then, and a wavering strength.
        if card.scanlines ~= nil and Rand(g) < (glitching and 0.6 or 0.12) then
            card.scanlines:SetRenderTranslation({ X = 0, Y = math.floor(Rand(g) * 3) })
            card.scanlines:SetRenderOpacity(0.7 + 0.6 * Rand(g))
        end
    end

    local moving = k < 1 or card.shakeAt ~= nil or card.popAt ~= nil or glitching or card.wasMoving
    if moving or not card.settled then
        card.root:SetRenderOpacity(opacity)
        card.root:SetRenderTranslation({ X = x, Y = y })
        card.root:SetRenderScale({ X = scale, Y = scale })
        card.settled = not moving
    end
    card.wasMoving = k < 1 or card.shakeAt ~= nil or card.popAt ~= nil or glitching

    if card.title ~= nil and s.motion.pulse then
        card.title:SetRenderOpacity(0.8 + 0.2 * (0.5 + 0.5 * math.sin(now * 3)))
    end

    if card.cursor ~= nil then
        local on = (now * 2) % 2 < 1
        if on ~= card.cursorOn then
            card.cursorOn = on
            SetShown(card.cursor, on)
        end
    end

    if card.sweepBand ~= nil then
        -- The sweep and the interference band each pick a new speed every time they wrap around.
        local g = card.glitch
        card.sweepPos = card.sweepPos or 0
        card.noisePos = card.noisePos or 0.5
        card.sweepSpeed = card.sweepSpeed or 0.3
        card.noiseSpeed = card.noiseSpeed or 0.12
        local dt = math.min(0.1, now - (card.lastTick or now))
        card.sweepPos = card.sweepPos + dt * card.sweepSpeed
        card.noisePos = card.noisePos + dt * card.noiseSpeed
        if card.sweepPos > 1 then
            card.sweepPos = 0
            card.sweepSpeed = 0.18 + 0.35 * (g and Rand(g) or 0.5)
        end
        if card.noisePos > 1 then
            card.noisePos = 0
            card.noiseSpeed = 0.06 + 0.2 * (g and Rand(g) or 0.5)
        end
        card.sweepBand:SetRenderTranslation({ X = 0, Y = card.sweepPos * 620 - 60 })
        if card.noiseBand ~= nil then
            card.noiseBand:SetRenderTranslation({ X = 0, Y = card.noisePos * 620 - 40 })
        end
    end
    card.lastTick = now

    if card.sparkles ~= nil then
        for i, dot in ipairs(card.sparkles) do
            local v = math.max(0, math.sin(now * 1.1 + i * 1.9))
            dot:SetRenderOpacity(0.15 + 0.85 * v ^ 6)
        end
    end

    local level = 0.5 + 0.42 * math.sin(now * 0.7 + card.index)
    if card.progress ~= nil then
        card.progress:SetPercent(level)
    elseif card.segments ~= nil then
        local lit = math.floor(level * #card.segments + 0.5)
        if lit ~= card.litCount then
            card.litCount = lit
            for i, seg in ipairs(card.segments) do
                SetShown(seg, i <= lit)
            end
        end
    end

    if card.slider ~= nil and card.readout ~= nil then
        local v = card.slider:GetValue()
        if math.abs(v - card.lastValue) > 0.004 then
            card.lastValue = v
            card.readout:SetText(FText(string.format("%d%%", math.floor(v * 100 + 0.5))))
        end
    end
end

local function Tick()
    if not S.open then
        return
    end
    local ok, err = pcall(function()
        if S.clickLatch then
            S.clickLatch = false
            HandleClick()
        end
        if S.closeRequested then
            Close()
            return
        end
        local page = S.pages[S.page]
        if page == nil then
            return
        end
        local now = os.clock()
        for _, card in ipairs(page.cards) do
            AnimateCard(card, now)
        end
        for _, watch in ipairs(page.hovers) do
            local hovered, pressed = false, false
            pcall(function()
                hovered = watch.widget:IsHovered() == true
                pressed = hovered and watch.widget:IsPressed() == true
            end)
            if hovered ~= watch.hovered or pressed ~= watch.pressed then
                watch.hovered, watch.pressed = hovered, pressed
                pcall(watch.fn, hovered, pressed)
            end
        end
    end)
    if not ok and not S.tickError then
        S.tickError = true
        Say("tick raised: " .. tostring(err))
    end
end

-- UE4SS keeps a registry reference to each loop and keybind callback; S keeps the closures alive.
S.tickFn = Tick
S.tickHandle = LoopInGameThreadWithDelay(16, S.tickFn)

S.pageFns = {}
for i, def in ipairs(PAGES) do
    S.pageFns[i] = function()
        ShowPage(i)
    end
    RegisterKeyBind(Key[def.key], function()
        ExecuteInGameThread(S.pageFns[i])
    end)
end

RegisterKeyBind(Key.LEFT_MOUSE_BUTTON, function()
    if S.open then
        S.clickLatch = true
    end
end)

S.consoleFn = function()
    if S.open then
        Close()
    else
        ShowPage(S.page or 1)
    end
end
pcall(RegisterConsoleCommandHandler, "stylelab", function()
    ExecuteInGameThread(S.consoleFn)
    return true
end)

Say("loaded " .. os.date("%Y-%m-%d %H:%M:%S") .. "; F6 to F11 show the pages; log at " .. LOG_PATH)
