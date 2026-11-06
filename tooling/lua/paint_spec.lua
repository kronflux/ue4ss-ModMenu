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

-- Stage 2 looks: gradients from strips, two-ring bevels, layered looks and the shift of a pressed
-- caption. Only the pure decisions are checked, because the spec cannot build a widget.
local black = { R = 0, G = 0, B = 0, A = 1 }
local white = { R = 1, G = 1, B = 1, A = 1 }
local ramp3 = Paint.Ramp({ black, white }, 3)
assert_eq("Ramp: three steps make three colours", #ramp3, 3)
assert_eq("Ramp: the first step is the first stop", ramp3[1], black)
assert_eq("Ramp: the middle step is grey 0.5", ramp3[2], { R = 0.5, G = 0.5, B = 0.5, A = 1 })
assert_eq("Ramp: the last step is the last stop", ramp3[3], white)
assert_eq("Ramp: one step is the first stop", Paint.Ramp({ black, white }, 1)[1], black)
local ramp3stops = Paint.Ramp({ black, white, black }, 3)
assert_eq("Ramp: a middle stop is reached exactly", ramp3stops[2], white)

local plan = Paint.GradientPlan({ black, white }, 4, 6, false)
assert_eq("GradientPlan: one entry per step", #plan, 4)
assert_eq("GradientPlan: the first strip rounds its top corners", plan[1].radii, { 6, 6, 0, 0 })
assert_eq("GradientPlan: the last strip rounds its bottom corners", plan[4].radii, { 0, 0, 6, 6 })
assert_true("GradientPlan: both ends are caps", plan[1].cap and plan[4].cap)
assert_eq("GradientPlan: a middle strip is square", plan[2].radii, { 0, 0, 0, 0 })
assert_eq("GradientPlan: a middle strip is not a cap", plan[2].cap, false)
assert_eq("GradientPlan: the first strip has the first colour", plan[1].color, black)
assert_eq("GradientPlan: the last strip has the last colour", plan[4].color, white)
local planH = Paint.GradientPlan({ black, white }, 4, 6, true)
assert_eq("GradientPlan: horizontal rounds the left corners first", planH[1].radii, { 6, 0, 0, 6 })
assert_eq("GradientPlan: horizontal rounds the right corners last", planH[4].radii, { 0, 6, 6, 0 })
local planFirst = Paint.GradientPlan({ black, white }, 4, 6, false, "first")
assert_eq("GradientPlan: roundEnds first keeps the last strip square", planFirst[4].radii, { 0, 0, 0, 0 })
assert_eq("GradientPlan: roundEnds first keeps the last strip not a cap", planFirst[4].cap, false)
assert_eq("GradientPlan: roundEnds first still rounds the first strip", planFirst[1].radii, { 6, 6, 0, 0 })
local planSquare = Paint.GradientPlan({ black, white }, 4, 0, false)
local anyCap = false
for _, strip in ipairs(planSquare) do
    anyCap = anyCap or strip.cap
end
assert_eq("GradientPlan: radius 0 caps no strip", anyCap, false)
assert_eq("GradientPlan: no step count gives twelve strips", #Paint.GradientPlan({ black, white }, nil, 0, false), 12)

local raised = { light = white, dark = black, innerLight = c, innerDark = outline }
local bevelPlan = Paint.BevelPlan(raised, false)
assert_eq("BevelPlan: two rings make eight lines", #bevelPlan, 8)
assert_eq("BevelPlan: outer top is light at inset 0", bevelPlan[1], { color = white, edge = "top", inset = 0 })
assert_eq("BevelPlan: outer left is light", bevelPlan[2], { color = white, edge = "left", inset = 0 })
assert_eq("BevelPlan: outer bottom is dark", bevelPlan[3], { color = black, edge = "bottom", inset = 0 })
assert_eq("BevelPlan: outer right is dark", bevelPlan[4], { color = black, edge = "right", inset = 0 })
assert_eq("BevelPlan: the inner ring sits one in", bevelPlan[5], { color = c, edge = "top", inset = 1 })
assert_eq("BevelPlan: inner bottom is the inner dark", bevelPlan[7], { color = outline, edge = "bottom", inset = 1 })
local sunkenPlan = Paint.BevelPlan(raised, true)
assert_eq("BevelPlan: sunken swaps the outer top to dark", sunkenPlan[1].color, black)
assert_eq("BevelPlan: sunken swaps the outer bottom to light", sunkenPlan[3].color, white)
assert_eq("BevelPlan: sunken swaps the inner top to the inner dark", sunkenPlan[5].color, outline)
assert_eq("BevelPlan: a single ring has four lines", #Paint.BevelPlan({ light = white, dark = black }, false), 4)
assert_eq("BevelPlan: a wider bevel puts the inner ring that far in", Paint.BevelPlan({
    light = white, dark = black, innerLight = c, innerDark = c, width = 2,
}, false)[5].inset, 2)
assert_eq("BevelPlan: a bevel without light or dark draws nothing", #Paint.BevelPlan({ width = 1 }, false), 0)
assert_eq("BevelPlan: no bevel draws nothing", #Paint.BevelPlan(nil, false), 0)

local gradientLook = { gradient = { stops = { black, white } } }
assert_eq("NeedsShapes: a gradient look needs shapes", Paint.NeedsShapes({ normal = gradientLook }), true)
assert_eq("NeedsShapes: a bevel look needs shapes", Paint.NeedsShapes({ normal = { fill = c, bevel = raised } }), true)
assert_eq("NeedsShapes: a layered look needs shapes", Paint.NeedsShapes({ normal = { layers = { flat } } }), true)
assert_eq("NeedsShapes: a gradient on hover needs shapes", Paint.NeedsShapes({ normal = flat, hover = gradientLook }), true)
assert_eq("NeedsShapes: a plain fill stays flat", Paint.NeedsShapes({ normal = { fill = c } }), false)

-- A shifted state moves the caption, and a state without a shift puts it back.
local function FakeLabel()
    local w = { moves = {} }
    function w:SetRenderTranslation(t)
        self.moves[#self.moves + 1] = t
    end
    return w
end
local label = FakeLabel()
local shiftShapes = { normal = FakeShape(), pressed = FakeShape() }
local shiftCtrl = {
    flat = false, shapes = shiftShapes, lastState = "normal", shownKey = "normal", label = label,
    looks = { normal = {}, pressed = { shift = { x = 1, y = 1 } } },
}
Paint.ShowState(shiftCtrl, "pressed")
assert_eq("ShowState: a shifted state moves the label", label.moves, { { X = 1, Y = 1 } })
Paint.ShowState(shiftCtrl, "normal")
assert_eq("ShowState: a state without a shift resets the label", label.moves, { { X = 1, Y = 1 }, { X = 0, Y = 0 } })
local content = FakeLabel()
local contentCtrl = {
    flat = false, shapes = { normal = FakeShape(), pressed = FakeShape() }, lastState = "normal",
    shownKey = "normal", content = content,
    looks = { normal = {}, pressed = { shift = { x = 2, y = 3 } } },
}
Paint.ShowState(contentCtrl, "pressed")
assert_eq("ShowState: with no label the content widget moves", content.moves, { { X = 2, Y = 3 } })
local plainCtrl = { flat = false, shapes = { normal = FakeShape(), hover = FakeShape() }, lastState = "normal",
    shownKey = "normal", label = FakeLabel(), looks = { normal = {}, hover = {} } }
Paint.ShowState(plainCtrl, "hover")
assert_eq("ShowState: a state that never shifted writes no translation", plainCtrl.label.moves, {})

local shownWidget = FakeShape()
Paint.SetShown(shownWidget, true)
Paint.SetShown(shownWidget, false)
assert_eq("SetShown: 3 shows and 2 hides", shownWidget.calls, { 3, 2 })

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

-- A bevel with nothing to draw wraps nothing, so the widget tree stays as it was.
local bevelContent = {}
assert_true("Bevelled returns the content when the bevel has no light or dark",
    Paint.Bevelled(nil, "n", bevelContent, { width = 1 }, true) == bevelContent)
assert_true("Bevelled returns the content when there is no bevel", Paint.Bevelled(nil, "n", bevelContent, nil, true) == bevelContent)
Util.Log = realLog
StaticFindObject = realFind
Paint.SetFonts({})
Paint.ResetSession()
