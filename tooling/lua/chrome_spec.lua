-- Specs for the window frames: which caption controls each look has and what they do, the traffic
-- lights, the shaded gradients, which header variants the shell draws, and how the caption controls
-- are polled. The shell modules require UEHelpers from the UE4SS install, so an empty stub stands in
-- while they load.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Chrome = require("ModMenu.shell.chrome")
local Build = require("ModMenu.shell.build")
local Close = require("ModMenu.shell.close")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end

-- Windows 11 has three caption buttons, 46 by 32, with close last. Minimise closes the menu and maximise does nothing.
local win11 = Chrome.Controls("win11", "all")
assert_eq("win11 all has three controls", #win11, 3)
assert_eq("win11 order is min, max, close", { win11[1].kind, win11[2].kind, win11[3].kind }, { "min", "max", "close" })
assert_eq("win11 close action is close", win11[3].action, "close")
assert_eq("win11 min action is close", win11[1].action, "close")
assert_eq("win11 max action is none", win11[2].action, "none")
assert_eq("win11 size is 46 by 32", win11[3].size, { 46, 32 })

-- XP buttons are 21 square and Classic ones are 16 by 14.
assert_eq("xp size is 21 by 21", Chrome.Controls("xp", "all")[1].size, { 21, 21 })
assert_eq("classic size is 16 by 14", Chrome.Controls("classic", "all")[2].size, { 16, 14 })

-- Captions "close" keeps only the close button.
local onlyClose = Chrome.Controls("xp", "close")
assert_eq("xp close captions returns one entry", #onlyClose, 1)
assert_eq("xp close captions entry is close", onlyClose[1].kind, "close")
assert_eq("a nil captions value means all", #Chrome.Controls("classic", nil), 3)
assert_eq("an unknown control style has no controls", #Chrome.Controls("beos", "all"), 0)

-- The traffic lights run close, minimise, maximise. Green only shows its looks.
local lights = Chrome.TrafficLights()
assert_eq("three traffic lights", #lights, 3)
assert_eq("light order", { lights[1].kind, lights[2].kind, lights[3].kind }, { "close", "min", "max" })
assert_eq("red closes", lights[1].action, "close")
assert_eq("yellow closes", lights[2].action, "close")
assert_eq("green does nothing", lights[3].action, "none")
assert_true("each light has a fill and an ink colour", lights[1].fill.R > 0.9 and lights[1].ink.R < 0.1)

-- Header variants map to a control style.
assert_eq("window uses win11 controls", Chrome.ControlStyle("window"), "win11")
assert_eq("xpbar uses xp controls", Chrome.ControlStyle("xpbar"), "xp")
assert_eq("classic uses classic controls", Chrome.ControlStyle("classic"), "classic")
assert_eq("mac has no caption controls", Chrome.ControlStyle("mac"), nil)

-- Shade mixes every stop towards a colour, for the lit and dark XP gradients.
local shaded = Chrome.Shade({ { R = 0, G = 0, B = 0, A = 1 }, { R = 1, G = 0.5, B = 0, A = 1 } }, { R = 1, G = 1, B = 1, A = 1 }, 0.25)
assert_eq("shade keeps the stop count", #shaded, 2)
assert_eq("shade lifts black a quarter towards white", shaded[1].R, 0.25)
assert_eq("shade lifts the second red channel", shaded[2].R, 1)
assert_eq("shade lifts green 0.5 to 0.625", shaded[2].G, 0.625)

-- XP caption glyphs are white unless the header sets captionGlyph.
local darkInk = { R = 0.02, G = 0.02, B = 0.04, A = 1 }
assert_eq("xp glyphs are white by default", Chrome.XpGlyphInk({}), { R = 1, G = 1, B = 1, A = 1 })
assert_eq("a header with other fields keeps white xp glyphs", Chrome.XpGlyphInk({ controlGlyph = darkInk }), { R = 1, G = 1, B = 1, A = 1 })
assert_eq("header.captionGlyph colours the xp glyphs", Chrome.XpGlyphInk({ captionGlyph = darkInk }), darkInk)

-- The XP and Classic title text follows title.color, and is white only when the style sets none.
local darkTitle = { R = 0.004, G = 0.005, B = 0.005, A = 1 }
local whiteTitle = { R = 1, G = 1, B = 1, A = 1 }
assert_eq("a dark title.color gives dark band title text", Chrome.BandTitleColor({ title = { color = darkTitle } }), darkTitle)
assert_eq("a white title.color gives white band title text", Chrome.BandTitleColor({ title = { color = whiteTitle } }), whiteTitle)
assert_eq("no title colour gives white band title text", Chrome.BandTitleColor({ title = {} }), whiteTitle)

-- The shell draws the new header variants, and still draws an unknown name as the badge.
assert_eq("an xpbar definition is an xpbar header", Build.HeaderVariant({ header = { variant = "xpbar" } }), "xpbar")
assert_eq("a window definition is a window header", Build.HeaderVariant({ header = { variant = "window" } }), "window")
assert_eq("a mac definition is a mac header", Build.HeaderVariant({ header = { variant = "mac" } }), "mac")
assert_eq("a classic definition is a classic header", Build.HeaderVariant({ header = { variant = "classic" } }), "classic")
assert_eq("an unknown header name is a badge", Build.HeaderVariant({ header = { variant = "beos" } }), "badge")
assert_eq("no style is the stock header", Build.HeaderVariant(nil), "stock")

-- A control with action none never closes the menu; every other control does.
assert_eq("action none does not close", Close.ClosesMenu({ action = "none" }), false)
assert_eq("action close closes", Close.ClosesMenu({ action = "close" }), true)
assert_eq("a plain Close control closes", Close.ClosesMenu({}), true)

-- onState runs once for each change of the shown state, and not on the polls in between.
local seen = {}
local ctrl = { notifiedState = "normal", lastState = "normal", onState = function(state)
    seen[#seen + 1] = state
end }
Close.NotifyState(ctrl)
assert_eq("no call while the state is unchanged", #seen, 0)
ctrl.lastState = "hover"
Close.NotifyState(ctrl)
Close.NotifyState(ctrl)
assert_eq("one call for one change", seen, { "hover" })
ctrl.lastState = "normal"
Close.NotifyState(ctrl)
assert_eq("the next change calls again", seen, { "hover", "normal" })
local noHook = { lastState = "hover" }
Close.NotifyState(noHook)
assert_true("a control without onState is left alone", noHook.notifiedState == nil)

-- A classic caption button shows a press even on a panel with no bevel, by deriving one from its face.
local face = { R = 0.5, G = 0.5, B = 0.5, A = 1 }
local plain = Chrome.ClassicStates(face, nil)
assert_true("classic without a panel bevel still has a bevel", plain.normal.bevel ~= nil and plain.normal.bevel.light.R > 0.5)
assert_true("the derived dark edge is darker than the face", plain.normal.bevel.dark.R < 0.5)
assert_eq("classic pressed shifts the symbol", plain.pressed.shift, { x = 1, y = 1 })
assert_eq("classic pressed is sunken", plain.pressed.sunken, true)
assert_true("a bevel with no light colour is replaced", Chrome.ClassicStates(face, { width = 1 }).normal.bevel.light ~= nil)
local own = { light = { R = 1, G = 1, B = 1, A = 1 }, dark = { R = 0, G = 0, B = 0, A = 1 } }
assert_true("the panel's own bevel is kept", Chrome.ClassicStates(face, own).normal.bevel == own)
