local Theme = require("ModMenu.core.theme")

-- These checks cover the colour shading and the button state colours, because the button widget paints hover and press from them every time its state changes.
local grey = { R = 0.5, G = 0.5, B = 0.5, A = 1 }

assert_eq("Shade lightens toward white", Theme.Shade(grey, 0.12), { R = 0.56, G = 0.56, B = 0.56, A = 1 })
assert_eq("Shade darkens toward black", Theme.Shade(grey, -0.12), { R = 0.44, G = 0.44, B = 0.44, A = 1 })
assert_eq("Shade clamps at 1", Theme.Shade(grey, 2), { R = 1, G = 1, B = 1, A = 1 })
assert_eq("Shade clamps at 0", Theme.Shade(grey, -2), { R = 0, G = 0, B = 0, A = 1 })
assert_eq(
    "Shade keeps alpha",
    Theme.Shade({ R = 0.2, G = 0.4, B = 0.6, A = 0.5 }, 0.5),
    { R = 0.6, G = 0.7, B = 0.8, A = 0.5 }
)
assert_true("Shade returns a new table", Theme.Shade(grey, 0.12) ~= grey)
assert_eq("Shade leaves its input alone", grey, { R = 0.5, G = 0.5, B = 0.5, A = 1 })

local dark = Theme.Preset("dark")
local primary = Theme.ButtonStates(dark, "primary")
assert_eq("primary hover derives from buttonBgPrimary", primary.hover, Theme.Shade(dark.buttonBgPrimary, 0.25))
assert_eq("primary pressed derives from buttonBgPrimary", primary.pressed, Theme.Shade(dark.buttonBgPrimary, -0.25))

local default = Theme.ButtonStates(dark, "default")
assert_eq("default hover derives from buttonBg", default.hover, Theme.Shade(dark.buttonBg, 0.25))
assert_eq("nil variant uses the default fill", Theme.ButtonStates(dark, nil).hover, Theme.Shade(dark.buttonBg, 0.25))

local explicitHover = { R = 0.9, G = 0.1, B = 0.1, A = 1 }
local merged = Theme.Merge(dark, { buttonPrimaryHover = explicitHover })
local explicit = Theme.ButtonStates(merged, "primary")
assert_eq("explicit buttonPrimaryHover wins", explicit.hover, explicitHover)
assert_eq("pressed still derives beside an explicit hover", explicit.pressed, Theme.Shade(dark.buttonBgPrimary, -0.25))

local explicitPressed = { R = 0.1, G = 0.1, B = 0.9, A = 1 }
local mergedDefault = Theme.Merge(dark, { buttonPressed = explicitPressed })
assert_eq("explicit buttonPressed wins for default", Theme.ButtonStates(mergedDefault, "default").pressed, explicitPressed)
