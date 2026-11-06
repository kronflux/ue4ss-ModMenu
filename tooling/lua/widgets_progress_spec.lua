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

-- Segments lit for a value, rounded down, 0 at min and every segment at max.
assert_eq("half the range lights half the segments", Progress.SegmentsLit(50, 0, 100, 12), 6)
assert_eq("min lights no segment", Progress.SegmentsLit(0, 0, 100, 12), 0)
assert_eq("max lights every segment", Progress.SegmentsLit(100, 0, 100, 12), 12)
assert_eq("just under max rounds down", Progress.SegmentsLit(99.9, 0, 100, 12), 11)
assert_eq("a value past max lights every segment", Progress.SegmentsLit(150, 0, 100, 12), 12)
assert_eq("a value below min lights none", Progress.SegmentsLit(-5, 0, 100, 12), 0)
assert_eq("an empty range lights none", Progress.SegmentsLit(5, 3, 3, 12), 0)
assert_eq("a fraction that floats just under a whole step still lights it", Progress.SegmentsLit(0.3, 0, 1, 10), 3)
assert_eq("a value that is not numeric lights none", Progress.SegmentsLit("x", 0, 1, 10), 0)

-- Themes. light and dark draw today's bar; slate draws its own.
local Style = require("ModMenu.core.style")
local light = Style.Resolve("light")
local slate = Style.Resolve("slate")
assert_eq("the light theme draws the stock bar", Progress.Variant(light, {}), "stock")
assert_eq("the dark theme draws the stock bar", Progress.Variant(Style.Resolve("dark"), {}), "stock")
assert_eq("slate draws its own progress variant", Progress.Variant(slate, {}), slate.progress.variant)
assert_eq("no resolved style draws the stock bar", Progress.Variant(nil, {}), "stock")
assert_eq("an item look picks segments", Progress.Variant(slate, { look = { variant = "segments" } }), "segments")

-- The themed fill is the theme's progress fill, unless the item names a button role.
local pr = Style.ForItem(slate, "progress", nil)
assert_eq("an unset variant fills with the progress fill", Progress.ThemedFill(pr, {}, slate), pr.fill)
assert_eq("a default variant fills with the progress fill", Progress.ThemedFill(pr, { variant = "default" }, slate), pr.fill)
assert_eq("a named variant fills with its role colour", Progress.ThemedFill(pr, { variant = "danger" }, slate), slate.button.roles.danger.fill)

-- A ramp colours segments by their place along the bar, or in turn when cycle is set.
local red, green, blue = { R = 1, G = 0, B = 0, A = 1 }, { R = 0, G = 1, B = 0, A = 1 }, { R = 0, G = 0, B = 1, A = 1 }
local rampSpec = { segments = 6, ramp = { red, green, blue } }
assert_eq("without a ramp a segment takes the fill", Progress.SegmentColor({ segments = 6 }, 3, green), green)
assert_eq("the first segment takes the first ramp colour", Progress.SegmentColor(rampSpec, 1, green), red)
assert_eq("segment 3 of 6 takes the second of 3 colours", Progress.SegmentColor(rampSpec, 3, green), green)
assert_eq("the last segment takes the last ramp colour", Progress.SegmentColor(rampSpec, 6, green), blue)
rampSpec.cycle = true
assert_eq("a cycling ramp starts again after its last colour", Progress.SegmentColor(rampSpec, 4, green), red)
-- The ramp spreads over the cells built, so a fractional or zero segments value never divides by zero.
local oddSpec = { segments = 0, ramp = { red, green, blue } }
assert_eq("a zero segments value builds one cell with the first ramp colour", Progress.SegmentColor(oddSpec, 1, green), red)
oddSpec.segments = 3.7
assert_eq("a fractional segments value spreads over the whole cells", Progress.SegmentColor(oddSpec, 3, green), blue)
assert_eq("the built count passed in wins over the raw value", Progress.SegmentColor(oddSpec, 2, green, 6), red)

-- A segmented bar shows a lit block by its visibility, so apply changes only the blocks whose state changed.
local shown = {}
local function fakeBlock(i)
    return {
        SetVisibility = function(_, v)
            shown[i] = v
        end,
    }
end
local segCtrl = {
    item = { id = "p", min = 0, max = 10 },
    valueKey = "s.p",
    segments = { fakeBlock(1), fakeBlock(2), fakeBlock(3), fakeBlock(4) },
    cellShown = { false, false, false, false },
    readout = { SetText = function() end },
}
local segCtx = { values = {} }
Progress.apply(segCtrl, 5, segCtx)
assert_eq("apply lights half the blocks", segCtrl.litCount, 2)
assert_eq("a lit block is shown hit-test invisible", shown[2], 3)
assert_eq("an unlit block is not touched when it was already unlit", shown[3], nil)
Progress.apply(segCtrl, 2.5, segCtx)
assert_eq("lowering the value hides the block above", shown[2], 2)
assert_eq("lowering the value keeps the block below lit", shown[1], 3)

-- A block whose call failed keeps no recorded state, so the next paint writes it again.
local failing = true
local retried = {}
local flaky = {
    SetVisibility = function(_, v)
        if failing then
            error("not ready")
        end
        retried[#retried + 1] = v
    end,
}
local flakyCtrl = {
    item = { id = "p", min = 0, max = 10 },
    valueKey = "s.p",
    segments = { flaky },
    readout = { SetText = function() end },
}
Progress.apply(flakyCtrl, 10, { values = {} })
assert_eq("a failed block records no shown state", flakyCtrl.cellShown[1], nil)
failing = false
Progress.apply(flakyCtrl, 10, { values = {} })
assert_eq("the same value writes a failed block again", retried[1], 3)
assert_eq("a written block records its shown state", flakyCtrl.cellShown[1], true)
-- The trough frame is chosen by its fields: a usable bevel wins, then an edge, and anything else draws no frame.
local frameEdge = { r = 1, g = 1, b = 1, a = 1 }
local edgeSpec = Progress.FrameSpec({ frame = { edge = frameEdge, radius = 4, pad = 2 } })
assert_eq("a frame with an edge is kind edge", edgeSpec.kind, "edge")
assert_eq("a frame keeps its pad", edgeSpec.pad, 2)
local bevelSpec = Progress.FrameSpec({ frame = { fill = frameEdge, bevel = { light = frameEdge, dark = frameEdge } } })
assert_eq("a frame with a fill and a bevel is kind bevel", bevelSpec.kind, "bevel")
assert_eq("a frame pad defaults to 2", bevelSpec.pad, 2)
assert_eq("a progress style without a frame is kind none", Progress.FrameSpec({}).kind, "none")
assert_eq("a nil progress style is kind none", Progress.FrameSpec(nil).kind, "none")
assert_eq("a frame with neither an edge nor a usable bevel is kind none",
    Progress.FrameSpec({ frame = { fill = frameEdge, bevel = { width = 1 } } }).kind, "none")
assert_eq("a bevel with only a light colour draws nothing, so the frame is none",
    Progress.FrameSpec({ frame = { bevel = { light = frameEdge } } }).kind, "none")
assert_eq("an edge frame with a pad of 0 keeps it", Progress.FrameSpec({ frame = { edge = frameEdge, pad = 0 } }).pad, 0)
assert_eq("light and dark have no frame", Progress.FrameSpec(Style.Resolve("light").progress).kind, "none")
assert_eq("segments are still counted the same way", Progress.SegmentsLit(50, 0, 100, 12), 6)
