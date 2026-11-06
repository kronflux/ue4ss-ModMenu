local Paint = require("ModMenu.core.paint")

-- These checks cover the decisions paint makes without the engine: which shapes are flat, which
-- font a chain lands on, which pointer state a button shows, and how a brush and a state swap are
-- written. Engine calls are replaced by plain tables and recording functions.
local c = { R = 0.5, G = 0.25, B = 0.125, A = 1 }
local outline = { R = 1, G = 0, B = 0, A = 1 }

assert_true("IsFlat: a fill alone is flat", Paint.IsFlat({ fill = c }))
assert_true("IsFlat: radius 0 and width 0 are flat", Paint.IsFlat({ fill = c, radius = 0, width = 0 }))
assert_true("IsFlat: four zero radii are flat", Paint.IsFlat({ fill = c, radius = { 0, 0, 0, 0 } }))
assert_eq("IsFlat: radius 4 is not flat", Paint.IsFlat({ radius = 4 }), false)
assert_eq("IsFlat: one rounded corner is not flat", Paint.IsFlat({ radius = { 0, 6, 0, 0 } }), false)
assert_eq("IsFlat: pill is not flat", Paint.IsFlat({ pill = true }), false)
assert_eq("IsFlat: an outline width is not flat", Paint.IsFlat({ width = 1 }), false)

-- The finder stands in for StaticFindObject and LoadAsset: it knows only the Roboto path.
local ROBOTO = "/Engine/EngineFonts/Roboto.Roboto"
local robotoAsset = { name = "roboto asset" }
local asked = {}
local function find(path)
    asked[#asked + 1] = path
    if path == ROBOTO then
        return robotoAsset
    end
    return nil
end

Paint.SetFonts({ kanit = "/Game/Fonts/Kanit.Kanit" })
local font, missing = Paint.PickFont({ "kanit", "roboto" }, find)
assert_true("PickFont: falls to roboto when kanit is missing", font == robotoAsset)
assert_eq("PickFont: names kanit as missing", missing, { "kanit" })
assert_eq("PickFont: looks kanit up through config.fonts", asked[1], "/Game/Fonts/Kanit.Kanit")

local endFont, endMissing = Paint.PickFont({ "kanit" }, find)
assert_true("PickFont: a chain without roboto still ends at roboto", endFont == robotoAsset)
assert_eq("PickFont: the implicit roboto is not missing", endMissing, { "kanit" })

local single = Paint.PickFont("roboto", find)
assert_true("PickFont: a single id string is a chain of one", single == robotoAsset)

local unknownFont, unknownMissing = Paint.PickFont({ "nosuchfont" }, find)
assert_true("PickFont: an id with no path falls to roboto", unknownFont == robotoAsset)
assert_eq("PickFont: an id with no path is missing", unknownMissing, { "nosuchfont" })

local noneFont, noneMissing = Paint.PickFont(nil, find)
assert_true("PickFont: no chain picks no font, so the engine font stays", noneFont == nil)
assert_eq("PickFont: no chain has nothing missing", noneMissing, {})

local monoAsked = nil
Paint.PickFont({ "mono" }, function(path)
    monoAsked = monoAsked or path
    return nil
end)
assert_eq("PickFont: mono is a built-in id", monoAsked, "/Engine/EngineFonts/DroidSansMono.DroidSansMono")
Paint.SetFonts({})

assert_eq("StateFor: hovered is hover", Paint.StateFor(true, false, true), "hover")
assert_eq("StateFor: hovered and pressed is pressed", Paint.StateFor(true, true, true), "pressed")
assert_eq("StateFor: disabled wins over pressed", Paint.StateFor(true, true, false), "disabled")
assert_eq("StateFor: idle is normal", Paint.StateFor(false, false, true), "normal")

local flat = { fill = c }
assert_eq("NeedsShapes: all flat and no edge keeps the legacy button", Paint.NeedsShapes({
    normal = flat,
    hover = flat,
    pressed = flat,
}), false)
assert_eq("NeedsShapes: a normal state alone keeps the legacy button", Paint.NeedsShapes({ normal = flat }), false)
assert_eq("NeedsShapes: a rounded hover state needs shapes", Paint.NeedsShapes({
    normal = flat,
    hover = { fill = c, radius = 6 },
}), true)
assert_eq("NeedsShapes: a pill disabled state needs shapes", Paint.NeedsShapes({
    normal = flat,
    disabled = { fill = c, pill = true },
}), true)
assert_eq("NeedsShapes: an edge needs shapes", Paint.NeedsShapes({
    normal = flat,
    edge = { outline = outline, width = 1 },
}), true)

-- A brush is written into the struct the widget owns, so a plain table with the same fields
-- shows exactly what was written.
local function NewBrush()
    return { TintColor = {}, OutlineSettings = { Color = {} } }
end

local rounded = NewBrush()
Paint.Brush(rounded, { fill = c, radius = { 1, 2, 3, 4 } })
assert_eq("Brush: rounded draws as a rounded box", rounded.DrawAs, 4)
assert_eq("Brush: corner radii go top-left, top-right, bottom-right, bottom-left", rounded.OutlineSettings.CornerRadii, {
    X = 1,
    Y = 2,
    Z = 3,
    W = 4,
})
assert_eq("Brush: the fill is the tint", rounded.TintColor.SpecifiedColor, c)
assert_eq("Brush: the tint uses the specified colour", rounded.TintColor.ColorUseRule, 0)
assert_eq("Brush: with width 0 the outline colour is the fill", rounded.OutlineSettings.Color.SpecifiedColor, c)
assert_eq("Brush: fixed rounding when not a pill", rounded.OutlineSettings.RoundingType, 0)

local box = NewBrush()
Paint.Brush(box, { fill = c })
assert_eq("Brush: flat draws as a box", box.DrawAs, 1)

local pill = NewBrush()
Paint.Brush(pill, { fill = c, pill = true, outline = outline, width = 2 })
assert_eq("Brush: a pill rounds at half height", pill.OutlineSettings.RoundingType, 1)
assert_eq("Brush: a pill draws as a rounded box", pill.DrawAs, 4)
assert_eq("Brush: an outline width uses the outline colour", pill.OutlineSettings.Color.SpecifiedColor, outline)
assert_eq("Brush: the outline width is written", pill.OutlineSettings.Width, 2)

-- A fake widget records each visibility it is given, so a swap shows which shapes were touched.
local function FakeShape()
    local w = { calls = {} }
    function w:SetVisibility(v)
        self.calls[#self.calls + 1] = v
    end
    return w
end

local shapes = { normal = FakeShape(), hover = FakeShape(), pressed = FakeShape() }
local ctrl = { flat = false, shapes = shapes, lastState = "normal", shownKey = "normal" }
Paint.ShowState(ctrl, "hover")
assert_eq("ShowState: the hover shape is shown hit-test invisible", shapes.hover.calls, { 3 })
assert_eq("ShowState: the normal shape is hidden", shapes.normal.calls, { 2 })
assert_eq("ShowState: an untouched shape gets no call", shapes.pressed.calls, {})
Paint.ShowState(ctrl, "hover")
assert_eq("ShowState: the same state again makes no call", shapes.hover.calls, { 3 })
Paint.ShowState(ctrl, "disabled")
assert_eq("ShowState: disabled with no disabled shape shows normal", shapes.normal.calls, { 2, 3 })
assert_eq("ShowState: the state is remembered", ctrl.lastState, "disabled")

assert_eq("ShapeKey: pressed falls back to hover", Paint.ShapeKey({ normal = 1, hover = 1 }, "pressed"), "hover")
assert_eq("ShapeKey: hover falls back to normal", Paint.ShapeKey({ normal = 1 }, "hover"), "normal")

assert_eq("Caption: upper uppercases", Paint.Caption("Apply", { upper = true }), "APPLY")
assert_eq("Caption: no upper keeps the text", Paint.Caption("Apply", { upper = false }), "Apply")
assert_eq("Caption: no spec keeps the text", Paint.Caption("Apply", nil), "Apply")

assert_eq("Margin: a number pads every side", Paint.Margin(3), { Left = 3, Top = 3, Right = 3, Bottom = 3 })
assert_eq("Margin: four numbers go left, top, right, bottom", Paint.Margin({ 1, 2, 3, 4 }), {
    Left = 1,
    Top = 2,
    Right = 3,
    Bottom = 4,
})

assert_eq("ShadowDepth: no shadow has depth 0", Paint.ShadowDepth({ hardShadow = 0 }), 0)
assert_eq("ShadowDepth: a hard shadow is its depth", Paint.ShadowDepth({ hardShadow = 5, shadowLayers = { { 0.3, 9 } } }), 5)
assert_eq("ShadowDepth: layers use the last layer's depth", Paint.ShadowDepth({
    shadowLayers = { { 0.3, 3 }, { 0.2, 7 }, { 0.1, 12 } },
}), 12)
assert_eq("ShadowDepth: a last layer that is not a list is no shadow", Paint.ShadowDepth({ shadowLayers = { 5 } }), 0)
assert_eq("ShadowDepth: a negative depth is no shadow", Paint.ShadowDepth({ shadowLayers = { { 0.3, -4 } } }), 0)
assert_eq("ShadowDepth: a spec that is not a table is no shadow", Paint.ShadowDepth(true), 0)

-- Theme sizes are desktop sizes at fontScale 1; the config's sizes are already scaled.
local desktop = { fontItem = 16, fontScale = 1.5, pointerMode = "mouse", _fontOverride = {} }
assert_eq("TextSize: a theme size is scaled by fontScale", Paint.TextSize(desktop, 14, "fontItem"), 21)
assert_eq("TextSize: no theme size uses the config size", Paint.TextSize(desktop, nil, "fontItem"), 16)
local explicit = { fontItem = 30, fontScale = 1.5, _fontOverride = { fontItem = true } }
assert_eq("TextSize: an explicit Init size wins over the theme", Paint.TextSize(explicit, 14, "fontItem"), 30)
local touch = { fontItem = 28, fontScale = 1, pointerMode = "touch", touchFontScale = 2, _fontOverride = {} }
assert_eq("TextSize: touch multiplies a theme size", Paint.TextSize(touch, 13, "fontItem"), 26)
local touchDefault = { fontItem = 28, fontScale = 1, pointerMode = "touch", _fontOverride = {} }
assert_eq("TextSize: touch uses 1.75 when touchFontScale is unset", Paint.TextSize(touchDefault, 10, "fontItem"), 18)

-- SetFonts reports a change, so Init searches failed fonts again only when the map changed.
Paint.SetFonts({})
assert_eq("SetFonts: the same map is no change", Paint.SetFonts({}), false)
assert_eq("SetFonts: a new id is a change", Paint.SetFonts({ kanit = "/Game/Fonts/Kanit.Kanit" }), true)
assert_eq("SetFonts: the same entries again are no change", Paint.SetFonts({ kanit = "/Game/Fonts/Kanit.Kanit" }), false)
assert_eq("SetFonts: a changed path is a change", Paint.SetFonts({ kanit = "/Game/Fonts/Other.Other" }), true)
Paint.SetFonts({})

-- FindAsset and Font reach the engine through globals, so the spec installs stand-ins and removes
-- them afterwards. Util.Log is replaced to count what is logged.
local Util = require("ModMenu.core.util")
local realLog = Util.Log
local logs = {}
Util.Log = function(msg)
    logs[#logs + 1] = msg
end
local realFind = StaticFindObject
local alive = true
local lookups = 0
local fontObject = {}
function fontObject:IsValid()
    return alive
end
StaticFindObject = function(path)
    lookups = lookups + 1
    if path == ROBOTO then
        return fontObject
    end
    return nil
end
Paint.ResetSession()

assert_true("FindAsset: finds the asset", Paint.FindAsset(ROBOTO) == fontObject)
local before = lookups
Paint.FindAsset(ROBOTO)
assert_eq("FindAsset: a valid cached hit is not looked up again", lookups, before)
alive = false
Paint.FindAsset(ROBOTO)
assert_true("FindAsset: a collected cached hit is looked up again", lookups > before)
alive = true

logs = {}
Paint.Font({ "kanit" })
Paint.Font({ "kanit" })
local noPath = 0
for _, msg in ipairs(logs) do
    if msg:find("font id kanit has no path", 1, true) then
        noPath = noPath + 1
    end
end
assert_eq("Font: an id with no path is logged once per session", noPath, 1)

Paint.SetFonts({ vcr = "/Game/Fonts/Vcr.Vcr" })
logs = {}
Paint.FindAsset("/Game/Fonts/Vcr.Vcr")
Paint.FindAsset("/Game/Fonts/Vcr.Vcr")
assert_eq("FindAsset: a missing path is logged once", #logs, 1)
local missLookups = lookups
Paint.SetFonts({ vcr = "/Game/Fonts/Vcr.Vcr" })
Paint.FindAsset("/Game/Fonts/Vcr.Vcr")
assert_eq("FindAsset: an unchanged font map keeps the cached miss", lookups, missLookups)
Paint.SetFonts({ vcr = "/Game/Fonts/Vcr2.Vcr2" })
Paint.FindAsset("/Game/Fonts/Vcr.Vcr")
assert_true("FindAsset: a changed font map searches the miss again", lookups > missLookups)
assert_eq("FindAsset: the search again does not log the path twice", #logs, 1)

-- A brush whose struct rejects writes logs each area once, however many brushes fail.
logs = {}
local broken = setmetatable({}, {
    __index = function()
        error("no such field")
    end,
    __newindex = function()
        error("read-only field")
    end,
})
Paint.Brush(broken, { fill = c })
Paint.Brush(broken, { fill = c })
assert_eq("Brush: failed areas are logged once each per session", #logs, 3)

Util.Log = realLog
StaticFindObject = realFind
Paint.SetFonts({})
Paint.ResetSession()
