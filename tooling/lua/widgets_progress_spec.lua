-- The spec runs without the game, so it checks validate, the helpers the progress bar exposes and the registry calls.
local Widgets = require("ModMenu.widgets.init")
assert_true("the progress type is registered", Widgets.has("progress"))
local Progress = require("ModMenu.widgets.progress")

assert_eq("fraction of the midpoint", Progress._fraction(5, { min = 0, max = 10 }), 0.5)
assert_eq("fraction clamps above max to 1", Progress._fraction(15, { min = 0, max = 10 }), 1)
assert_eq("fraction clamps below min to 0", Progress._fraction(-3, { min = 0, max = 10 }), 0)
assert_eq("fraction counts from min", Progress._fraction(15, { min = 10, max = 20 }), 0.5)
assert_eq("fraction defaults to the range 0 to 1", Progress._fraction(0.25, {}), 0.25)
assert_eq("fraction of a value that is not numeric is 0", Progress._fraction("x", { min = 0, max = 10 }), 0)

assert_eq("coerce keeps a value in range", Progress._coerce(0.4, {}), 0.4)
assert_eq("coerce clamps above max", Progress._coerce(7, { min = 0, max = 5 }), 5)
assert_eq("coerce clamps below min", Progress._coerce(-2, { min = 0, max = 5 }), 0)
assert_eq("coerce reads a numeric string", Progress._coerce("3", { min = 0, max = 5 }), 3)
assert_eq("coerce rejects text", Progress._coerce("x", { min = 0, max = 5 }), nil)
assert_eq("coerce rejects nil", Progress._coerce(nil, { min = 0, max = 5 }), nil)
assert_eq("coerce does not snap to a step", Progress._coerce(0.123, {}), 0.123)

assert_eq("format shows the percent of the default range", Progress._format(0.25, { min = 0, max = 1 }), "25%")
assert_eq("format shows the percent of a custom range", Progress._format(15, { min = 10, max = 20 }), "50%")
assert_eq("format rounds the percent", Progress._format(0.666, {}), "67%")
assert_eq("format clamps a value past max to 100 percent", Progress._format(3, {}), "100%")
assert_eq("format uses a format string", Progress._format(0.25, { format = "%.2f of 1" }), "0.25 of 1")
assert_eq("format uses a format function", Progress._format(3, { min = 0, max = 10, format = function(v)
    return "step " .. v
end }), "step 3")
assert_eq("format falls back to the percent when the string fails", Progress._format(0.5, { format = "%q%q" }), "50%")
assert_eq("format falls back to the percent when the function fails", Progress._format(0.5, { format = function()
    error("boom")
end }), "50%")

-- A variant picks one of the theme's button fills, and an unset or default variant uses the accent.
local colors = { buttonBgPrimary = { R = 1 }, buttonBgDanger = { R = 2 }, textAccent = { R = 3 } }
assert_eq("an unset variant fills with the primary colour", Progress._fillColor({}, colors).R, 1)
assert_eq("a default variant fills with the primary colour", Progress._fillColor({ variant = "default" }, colors).R, 1)
assert_eq("a named variant fills with its button colour", Progress._fillColor({ variant = "danger" }, colors).R, 2)
assert_eq("a variant the theme lacks falls back to the accent", Progress._fillColor({ variant = "info" }, { textAccent = { R = 3 } }).R, 3)

local function validateError(extra)
    local item = { id = "p", label = "P" }
    for key, value in pairs(extra) do
        item[key] = value
    end
    local ok, err = pcall(Progress.validate, item, "s", 1)
    return (not ok) and tostring(err) or nil
end

local function says(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a bare progress item", validateError({}) == nil)
assert_true("validate accepts a full progress item", validateError({ min = 0, max = 10, default = 3, format = "%d", variant = "success" }) == nil)
assert_true("validate accepts a format function", validateError({ format = function() end }) == nil)
assert_true("validate requires an id", says(select(2, pcall(Progress.validate, { label = "P" }, "s", 1)), "requires .id"))
assert_true("validate requires a label", says(select(2, pcall(Progress.validate, { id = "p" }, "s", 1)), "requires .label"))
assert_true("validate names min", says(validateError({ min = "a" }), "min must be a number"))
assert_true("validate names max", says(validateError({ max = "a" }), "max must be a number"))
assert_true("validate names an inverted range", says(validateError({ min = 5, max = 5 }), "min must be less than max"))
assert_true("validate checks min against the default max of 1", says(validateError({ min = 2 }), "min must be less than max"))
assert_true("validate names a default that is not numeric", says(validateError({ default = "loud" }), "default must be numeric"))
assert_true("validate names format", says(validateError({ format = 3 }), "format must be a string or a function"))
assert_true("validate names variant", says(validateError({ variant = "loud" }), "variant must be default|primary|secondary|success|danger|warning|info"))
assert_true("validate error carries the section and item prefix", says(validateError({ min = "a" }), "Register(s) items[1]"))

local values = { ["s.early"] = "7" }
Progress.seed("s", { id = "p", label = "P", min = 0, max = 10, default = 4 }, values)
assert_eq("seed stores the default", values["s.p"], 4)
Progress.seed("s", { id = "early", label = "E", min = 0, max = 5 }, values)
assert_eq("seed coerces a value set before Register", values["s.early"], 5)
Progress.seed("s", { id = "bare", label = "B" }, values)
assert_eq("seed without a default or a min stores zero", values["s.bare"], 0)
Progress.seed("s", { id = "lo", label = "L", min = 2, max = 9 }, values)
assert_eq("seed without a default stores min", values["s.lo"], 2)

-- The registry stores a progress value clamped, whether or not the control is built.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Registry = require("ModMenu.shell.registry")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
local function makeState()
    return {
        values = { ["s.p"] = 0 },
        liveControls = {},
        sections = {
            {
                id = "s",
                items = {
                    { id = "p", type = "progress", label = "Load", min = 0, max = 10 },
                    { id = "t", type = "label", label = "Text" },
                    {
                        id = "r",
                        type = "row",
                        items = { { id = "q", type = "progress", label = "In a row" } },
                    },
                },
            },
        },
        sectionIndexById = { s = 1 },
        menuOpen = false,
        makeWidgetCtx = function()
            return {}
        end,
    }
end
local state = makeState()
assert_eq("SetValue on a progress item returns true", Registry.SetValue(state, "s", "p", 4), true)
assert_eq("Get returns the stored value", Registry.Get(state, "s", "p"), 4)
assert_eq("SetValue clamps above max", Registry.SetValue(state, "s", "p", 99), true)
assert_eq("Get returns the clamped value", Registry.Get(state, "s", "p"), 10)
Registry.SetValue(state, "s", "p", -5)
assert_eq("SetValue clamps below min", Registry.Get(state, "s", "p"), 0)
Registry.SetValue(state, "s", "p", "6")
assert_eq("SetValue reads a numeric string", Registry.Get(state, "s", "p"), 6)
assert_eq("SetValue with text returns false", Registry.SetValue(state, "s", "p", "abc"), false)
assert_eq("SetValue with text leaves the value", Registry.Get(state, "s", "p"), 6)
assert_eq("SetValue on an unknown item returns false", Registry.SetValue(state, "s", "nope", 1), false)
assert_eq("SetValue on an unknown section returns false", Registry.SetValue(state, "zzz", "p", 1), false)
assert_eq("SetValue on an item that is not a progress bar returns false", Registry.SetValue(state, "s", "t", 1), false)
assert_eq("SetValue reaches a progress bar inside a row", Registry.SetValue(state, "s", "q", 0.5), true)
assert_eq("Get returns the value of the bar in the row", Registry.Get(state, "s", "q"), 0.5)

Registry.Set(state, "s", "p", 99)
assert_eq("Set on a progress item clamps too", Registry.Get(state, "s", "p"), 10)
Registry.Set(state, "s", "p", "abc")
assert_eq("Set on a progress item ignores a value that is not a number", Registry.Get(state, "s", "p"), 10)

assert_eq("SetLabel on a progress item returns true", Registry.SetLabel(state, "s", "p", "Loading"), true)
assert_eq("SetLabel changes the progress item's label", state.sections[1].items[1].label, "Loading")
assert_eq("SetLabel still changes a label item", Registry.SetLabel(state, "s", "t", "New text"), true)
assert_eq("SetLabel still returns false for an unknown item", Registry.SetLabel(state, "s", "nope", "x"), false)

-- apply stores the clamped value and puts the last good value back for junk. It never raises without the game.
local ctrl = { kind = "progress", item = { id = "p", label = "P", min = 0, max = 1 }, valueKey = "s.p", value = 0.5 }
local ctx = {
    values = { ["s.p"] = 0.5 },
    IsValid = function(o)
        return o ~= nil
    end,
}
Progress.apply(ctrl, 3, ctx)
assert_eq("apply clamps and stores the value", ctx.values["s.p"], 1)
ctx.values["s.p"] = "abc"
Progress.apply(ctrl, "abc", ctx)
assert_eq("apply with junk puts the last good value back in the store", ctx.values["s.p"], 1)
assert_true("poll tolerates a control whose widget is gone", pcall(Progress.poll, ctrl, {
    IsValid = function()
        return false
    end,
}))
