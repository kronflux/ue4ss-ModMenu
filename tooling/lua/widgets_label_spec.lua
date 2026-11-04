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