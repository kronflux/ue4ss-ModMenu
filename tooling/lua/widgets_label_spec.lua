-- Label presentation settings are tested through validate, _style and the section validate, because
-- drawing the text needs UMG, which MoonSharp does not have.
-- The shell collapse module requires UEHelpers through the input module, so an empty stub stands in while it loads.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okLabel, Label = pcall(require, "ModMenu.widgets.label")
local okCollapse, Collapse = pcall(require, "ModMenu.shell.collapse")
local okTheme, Theme = pcall(require, "ModMenu.core.theme")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("widgets.label loads under MoonSharp", okLabel)
assert_true("shell.collapse loads under MoonSharp", okCollapse)
assert_true("core.theme loads under MoonSharp", okTheme)
if not (okLabel and okCollapse and okTheme) then
    return
end

local function errorOf(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        return nil
    end
    return tostring(err)
end

local function mentions(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a label with no presentation fields", pcall(Label.validate, { label = "L" }, "s", 1))
assert_true(
    "validate accepts every style, align and wrap",
    pcall(Label.validate, { label = "L", style = "warning", align = "right", wrap = false }, "s", 1)
)
assert_true(
    "validate rejects an unknown style and lists the allowed ones",
    mentions(errorOf(Label.validate, { label = "L", style = "loud" }, "s", 1), "style must be one of normal, muted, heading, warning")
)
assert_true(
    "validate rejects an unknown align and lists the allowed ones",
    mentions(errorOf(Label.validate, { label = "L", align = "middle" }, "s", 1), "align must be one of left, center, right")
)
assert_true(
    "validate rejects a non-boolean wrap",
    mentions(errorOf(Label.validate, { label = "L", wrap = "yes" }, "s", 1), "wrap must be a boolean")
)

-- _style gives the font size and colour for each style.
local colors = Theme.Preset("dark")
local config = { fontHint = 14, fontSection = 20 }
assert_eq("normal is the hint size in the primary text colour", Label._style({}, config, colors), { size = 14, color = colors.textPrimary })
assert_eq("muted is the hint size in the muted colour", Label._style({ style = "muted" }, config, colors), { size = 14, color = colors.textMuted })
assert_eq("heading is the section size in the accent colour", Label._style({ style = "heading" }, config, colors), { size = 20, color = colors.textAccent })
assert_eq("warning is the hint size in the status colour", Label._style({ style = "warning" }, config, colors), { size = 14, color = colors.textStatus })

-- _justify turns align into the engine's text justification: left 0, center 1, right 2.
assert_eq("align defaults to left", Label._justify({}), 0)
assert_eq("align center is justification 1", Label._justify({ align = "center" }), 1)
assert_eq("align right is justification 2", Label._justify({ align = "right" }), 2)

-- A section's description and prefix are strings.
local base = { id = "Main", items = {} }
assert_true("a section with a description and a prefix is valid", pcall(Collapse.Validate, { id = "Main", description = "d", prefix = "[x]", items = {} }))
assert_true("a section with no description or prefix is valid", pcall(Collapse.Validate, base))
assert_true(
    "a non-string section description is rejected",
    mentions(errorOf(Collapse.Validate, { id = "Main", description = 3, items = {} }), "Register(Main) description must be a string")
)
assert_true(
    "a non-string section prefix is rejected",
    mentions(errorOf(Collapse.Validate, { id = "Main", prefix = 3, items = {} }), "Register(Main) prefix must be a string")
)

-- Label.TextSpec maps each label style onto the resolved text styles of a theme.
local okStyle, Style = pcall(require, "ModMenu.core.style")
assert_true("core.style loads under MoonSharp", okStyle)
if okStyle then
    local slate = Style.Resolve("slate")
    assert_eq("heading takes the resolved section text size", Label.TextSpec(slate, "heading").size, slate.section.text.size)
    assert_eq("heading takes the resolved section text colour", Label.TextSpec(slate, "heading").color, slate.section.text.color)
    assert_eq("normal is the body colour", Label.TextSpec(slate, "normal").color, slate.body.color)
    assert_eq("a missing style is normal", Label.TextSpec(slate, nil).color, slate.body.color)
    assert_eq("muted is body in palette.muted", Label.TextSpec(slate, "muted").color, slate.palette.muted)
    assert_eq("warning is body in palette.warning", Label.TextSpec(slate, "warning").color, slate.palette.warning)
    local spec = Label.TextSpec(slate, "muted")
    spec.color = { R = 0, G = 0, B = 0, A = 0 }
    assert_eq("TextSpec returns a copy, so the resolved body keeps its colour", slate.body.color, Style.Resolve("slate").body.color)
    -- Light and dark keep today's labels and separators; slate draws them from its text styles.
    assert_true("light labels are stock", Label.Stock(Style.Resolve("light")))
    assert_true("dark labels are stock", Label.Stock(Style.Resolve("dark")))
    assert_true("slate labels are themed", not Label.Stock(slate))
    assert_true("no resolved theme is stock", Label.Stock(nil))
end

-- An item look is merged over the label's text style, on stock themes too.
if okStyle then
    local light = Style.Resolve("light")
    local slate = Style.Resolve("slate")
    local lightColors = Theme.Preset("light")
    -- #FF0000 is sRGB full red, which converts to linear 1, 0, 0.
    local red = Label.LookSpec(light, "normal", { color = "#FF0000" }, lightColors.textPrimary)
    assert_eq("a light label with a red look gets red", red.color, { R = 1, G = 0, B = 0, A = 1 })
    assert_eq("a light label look keeps the config size", red.size, nil)
    local fontOnly = Label.LookSpec(light, "heading", { font = "mono" }, lightColors.textAccent)
    assert_eq("a light look that sets only a font keeps the stock colour", fontOnly.color, lightColors.textAccent)
    assert_eq("a light look that sets a font carries it", fontOnly.font, "mono")
    local big = Label.LookSpec(slate, "heading", { size = 30 }, nil)
    assert_eq("a slate heading with a size look gets that size", big.size, 30)
    assert_eq("a size look keeps the heading's section text colour", big.color, slate.section.text.color)
    assert_eq("an empty look leaves the slate heading spec as it was", Label.LookSpec(slate, "heading", {}, nil), Label.TextSpec(slate, "heading"))
    assert_eq("a look does not change the resolved body", slate.body.color, Style.Resolve("slate").body.color)
end

-- A host's style override for body, hint or section takes labels off the stock path on light and
-- dark, and the label keeps its legacy colour wherever the override sets none.
if okStyle then
    local lightColors = Theme.Preset("light")
    local redStyle = { body = { color = "#FF0000" } }
    local redLight = Style.Resolve("light", redStyle)
    assert_true("light labels stay stock without a style override", Label.Stock(Style.Resolve("light"), {}))
    assert_true("light labels stay stock with only a button override", Label.Stock(Style.Resolve("light"), { button = { radius = 4 } }))
    assert_true("a body override takes light labels off the stock path", not Label.Stock(redLight, redStyle))
    assert_true("a hint override takes light labels off the stock path", not Label.Stock(Style.Resolve("light", { hint = { size = 12 } }), { hint = { size = 12 } }))
    assert_true("a section override takes dark labels off the stock path", not Label.Stock(Style.Resolve("dark", { section = { color = "#00FF00" } }), { section = { color = "#00FF00" } }))
    local red = Label.StockSpec(redLight, "normal", redStyle, lightColors.textPrimary)
    assert_eq("a light label under a red body override gets red", red.color, { R = 1, G = 0, B = 0, A = 1 })
    assert_eq("a light label under a colour-only override keeps the config size", red.size, nil)
    local plain = Label.StockSpec(Style.Resolve("light"), "normal", nil, lightColors.textPrimary)
    assert_eq("a light label without a style keeps the legacy colour", plain.color, lightColors.textPrimary)
    local muted = Label.StockSpec(redLight, "muted", redStyle, lightColors.textMuted)
    assert_eq("a muted light label keeps its legacy colour under a body colour override", muted.color, lightColors.textMuted)
    local fontStyle = { body = { font = "mono" } }
    local font = Label.StockSpec(Style.Resolve("light", fontStyle), "normal", fontStyle, lightColors.textPrimary)
    assert_eq("a font-only body override keeps the legacy colour", font.color, lightColors.textPrimary)
    assert_eq("a font-only body override carries the font", font.font, "mono")
    local headStyle = { section = { color = "#00FF00" } }
    local head = Label.StockSpec(Style.Resolve("light", headStyle), "heading", headStyle, lightColors.textAccent)
    assert_eq("a section colour override colours a light heading", head.color, { R = 0, G = 1, B = 0, A = 1 })
    local lookOver = Label.LookSpec(redLight, "normal", { font = "mono" }, lightColors.textPrimary, redStyle)
    assert_eq("a look over a body override keeps the override colour", lookOver.color, { R = 1, G = 0, B = 0, A = 1 })
end
