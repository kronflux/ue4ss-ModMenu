-- The spec runs without the game, so it checks validate and the helpers the slider exposes.
local Slider = require("ModMenu.widgets.slider")

assert_eq("coerce snaps to the nearest step", Slider._coerce(7.3, { min = 0, max = 10, step = 0.5 }), 7.5)
assert_eq("coerce clamps a numeric string above max", Slider._coerce("12", { min = 0, max = 10 }), 10)
assert_eq("coerce clamps below min", Slider._coerce(-4, { min = 0, max = 10 }), 0)
assert_eq("coerce snaps from min, not from zero", Slider._coerce(2.2, { min = 1, max = 9, step = 2 }), 3)
assert_eq("coerce keeps max reachable off the step grid", Slider._coerce(10, { min = 0, max = 10, step = 3 }), 10)
assert_eq("coerce rounds an integer item", Slider._coerce(2.5, { min = 0, max = 10, integer = true }), 3)
assert_eq("coerce rejects a non-numeric string", Slider._coerce("abc", { min = 0, max = 10 }), nil)
assert_eq("coerce of nil resets to the default", Slider._coerce(nil, { min = 0, max = 10, default = 4 }), 4)
assert_eq("coerce of nil without a default resets to min", Slider._coerce(nil, { min = 2, max = 10 }), 2)

-- A slider set before it is built is coerced in the registry, the same way a number item is.
-- The registry requires UEHelpers through the shell build module, so an empty stub stands in while it loads.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Registry = require("ModMenu.shell.registry")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
local unbuilt = {
    values = {},
    liveControls = {},
    sections = { { id = "s", items = { { id = "v", type = "slider", label = "V", min = 0, max = 10, step = 0.5, default = 2 } } } },
    sectionIndexById = { s = 1 },
    menuOpen = false,
    makeWidgetCtx = function()
        return {}
    end,
}
Registry.Set(unbuilt, "s", "v", "7.3")
assert_eq("Set on an unbuilt slider snaps text to the step", unbuilt.values["s.v"], 7.5)
Registry.Set(unbuilt, "s", "v", 99)
assert_eq("Set on an unbuilt slider clamps a number above max to max", unbuilt.values["s.v"], 10)
Registry.Set(unbuilt, "s", "v", "abc")
assert_eq("Set on an unbuilt slider ignores a value that is not a number", unbuilt.values["s.v"], 10)

assert_eq("fraction of the midpoint is a half", Slider._fraction(5, { min = 0, max = 10 }), 0.5)
assert_eq("fraction clamps below min to zero", Slider._fraction(-3, { min = 0, max = 10 }), 0)
assert_eq("fraction clamps above max to one", Slider._fraction(30, { min = 0, max = 10 }), 1)
assert_eq("valueAt maps a fraction onto the range and snaps it", Slider._valueAt(0.33, { min = 0, max = 10, step = 1 }), 3)

assert_eq("format trims trailing zeros", Slider._format(7.5, { min = 0, max = 10 }), "7.5")
assert_eq("format writes an integer item without a point", Slider._format(3, { min = 0, max = 10, integer = true }), "3")
assert_eq("format uses a format string", Slider._format(0.25, { min = 0, max = 1, format = "%.2f" }), "0.25")
assert_eq(
    "format uses a format function",
    Slider._format(2, { min = 0, max = 10, format = function(v)
        return v .. " m"
    end }),
    "2 m"
)

local function validateError(item)
    local ok, err = pcall(Slider.validate, item, "s", 1)
    if ok then
        return nil
    end
    return tostring(err)
end

local function names(err, word)
    return err ~= nil and string.find(err, word, 1, true) ~= nil
end

local good = { id = "v", label = "Volume", min = 0, max = 10, default = 5, step = 0.5 }
assert_true("validate accepts a full slider item", pcall(Slider.validate, good, "s", 1))
assert_true("validate names min when it is missing", names(validateError({ id = "v", label = "V", max = 10 }), "min"))
assert_true("validate names max when it is missing", names(validateError({ id = "v", label = "V", min = 0 }), "max"))
assert_true(
    "validate names min and max when min is not below max",
    names(validateError({ id = "v", label = "V", min = 5, max = 5 }), "min must be less than max")
)
assert_true(
    "validate names step when it is not positive",
    names(validateError({ id = "v", label = "V", min = 0, max = 10, step = 0 }), "step")
)
assert_true(
    "validate names default when it is not numeric",
    names(validateError({ id = "v", label = "V", min = 0, max = 10, default = "loud" }), "default")
)
assert_true(
    "validate names format when it is neither a string nor a function",
    names(validateError({ id = "v", label = "V", min = 0, max = 10, format = 3 }), "format")
)
assert_true(
    "validate names live when it is not a boolean",
    names(validateError({ id = "v", label = "V", min = 0, max = 10, live = "yes" }), "live")
)

local values = { ["s.early"] = "12" }
Slider.seed("s", good, values)
assert_eq("seed stores the default", values["s.v"], 5)
Slider.seed("s", { id = "early", label = "E", min = 0, max = 10, step = 1 }, values)
assert_eq("seed coerces a value set before Register", values["s.early"], 10)

-- The stub ctx carries only the fields apply reads. Painting fails on the missing FText global inside a pcall.
local calls = 0
local item = { id = "v", label = "Volume", min = 0, max = 10, step = 0.5, onChange = function()
    calls = calls + 1
end }
local ctrl = { kind = "slider", item = item, valueKey = "s.v", lastFired = 5 }
local ctx = {
    values = values,
    IsValid = function(o)
        return o ~= nil
    end,
}
Slider.apply(ctrl, "7.3", ctx)
assert_eq("apply coerces and stores the value", values["s.v"], 7.5)
-- The registry's Set coerces a slider value before it stores it, and ignores one that is not numeric.
-- Apply still guards against such a value in the store, so the spec writes it there before the call.
values["s.v"] = "abc"
Slider.apply(ctrl, "abc", ctx)
assert_eq("apply with junk puts the last good value back in the store", values["s.v"], 7.5)
values["s.v"] = nil
Slider.apply(ctrl, nil, ctx)
assert_eq("apply with nil resets to the default", values["s.v"], 0)
assert_eq("apply never calls onChange", calls, 0)
