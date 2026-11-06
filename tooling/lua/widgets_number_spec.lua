local Number = require("ModMenu.widgets.number")

local range = { min = 0, max = 10 }

assert_eq("a numeric string becomes a clamped number", Number._coerce("5", range), 5)
assert_eq("a non-numeric string is rejected", Number._coerce("abc", range), nil)
assert_eq("an empty string is rejected", Number._coerce("", range), nil)
assert_eq("a string above max is clamped to max", Number._coerce("12", range), 10)
assert_eq(
    "an integer item rounds a fractional string like a number argument",
    Number._coerce("2.7", { min = 0, max = 10, integer = true }),
    3
)
assert_eq(
    "an integer item rounds a negative string away from zero",
    Number._coerce("-2.7", { min = -10, max = 10, integer = true }),
    -3
)
assert_eq(
    "an integer item keeps a whole negative string",
    Number._coerce("-3", { min = -10, max = 10, integer = true }),
    -3
)
-- tonumber ignores surrounding whitespace, so a padded string is accepted as its number.
assert_eq("a whitespace-padded string is accepted", Number._coerce(" 5 ", range), 5)
-- Set(nil) resets a number item, so nil coerces to the item's default after rounding and clamping.
assert_eq(
    "Set(nil) resets to the default",
    Number._coerce(nil, { min = 0, max = 10, integer = true, default = 12.4 }),
    10
)
assert_eq("Set(nil) without a default resets to zero", Number._coerce(nil, range), 0)

local negItem = { id = "neg", label = "Neg", integer = true, min = -10, max = 10, default = -3 }
local negValues = {}
Number.seed("s", negItem, negValues)
assert_eq("a negative integer default seeds unchanged", negValues["s.neg"], -3)
assert_eq("a negative integer formats unchanged", Number._formatValue(-3, true), "-3")
assert_eq("typed negative text rounds away from zero", Number._parseText("-2.7", negItem), -3)

local item = { id = "n", label = "N", min = 0, max = 10, default = 3 }
assert_true("validate accepts a number item with min, max and default", pcall(Number.validate, item, "s", 1))

local values = {}
Number.seed("s", item, values)
assert_eq("seed stores the default", values["s.n"], 3)

-- A Set before Register leaves the raw value in the store, so seed must coerce it as Set does after Register.
local early = { ["s.n"] = "12", ["s.j"] = "abc" }
Number.seed("s", item, early)
Number.seed("s", { id = "j", label = "J", default = 4 }, early)
assert_eq("seed coerces a string set before Register", early["s.n"], 10)
assert_eq("seed replaces a non-numeric value set before Register with the default", early["s.j"], 4)

-- The stub ctx carries only the fields apply reads, so no UE4SS global is needed.
-- SetText fails on the missing FText global inside apply's pcall, which apply already tolerates.
-- Set never fires onChange because the host supplied the value, so apply must not call it.
local calls = 0
item.onChange = function()
    calls = calls + 1
end
local ctrl = {
    kind = "number",
    item = item,
    edit = {},
    valueKey = "s.n",
    lastFiredOnChange = 3,
}
local ctx = {
    values = values,
    liveControls = {},
    SafeCall = function(fn, ...)
        if type(fn) == "function" then
            pcall(fn, ...)
        end
    end,
    IsValid = function(o)
        return o ~= nil
    end,
}
Number.apply(ctrl, "5", ctx)
assert_eq("apply with a numeric string stores the number", values["s.n"], 5)
Number.apply(ctrl, "abc", ctx)
assert_eq("apply with junk keeps the number", values["s.n"], 5)
assert_eq("apply never calls onChange", calls, 0)

-- step is what the minus and plus buttons add. The value stays inside the range.
local stepItem = { min = 0, max = 10, step = 2 }
assert_eq("a plus step adds the step", Number._step(4, 1, stepItem), 6)
assert_eq("a plus step stops at max", Number._step(9, 1, stepItem), 10)
assert_eq("a minus step stops at min", Number._step(1, -1, stepItem), 0)
assert_eq("an integer item rounds a fractional step", Number._step(1, 1, { min = 0, max = 10, step = 0.5, integer = true }), 2)

local function stepError(item)
    local ok, err = pcall(Number.validate, item, "s", 1)
    return (not ok) and tostring(err) or nil
end
local function stepMentions(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end
assert_true("a number with a step, prefix and suffix is valid", pcall(Number.validate, { id = "n", label = "N", step = 0.5, prefix = "$", suffix = "ms" }, "s", 1))
assert_true("a zero step is rejected", stepMentions(stepError({ id = "n", label = "N", step = 0 }), "step must be a positive number"))
assert_true("a non-string prefix is rejected", stepMentions(stepError({ id = "n", label = "N", prefix = 1 }), "prefix must be a string"))
assert_true("a non-string suffix is rejected", stepMentions(stepError({ id = "n", label = "N", suffix = 1 }), "suffix must be a string"))

-- Disabling the number drops a press on its step buttons, so enabling it again cannot fire a stale step.
local stubbedNumberHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedNumberHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local NumberInput = require("ModMenu.core.input")
if stubbedNumberHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
local heldStep = { dir = 1, holding = true, armed = true, armTicks = 1 }
local steppedCtrl = { kind = "number", item = stepItem, stepButtons = { heldStep } }
Number.onItemState(steppedCtrl, false, true, { Input = NumberInput })
assert_eq("disabling a number clears a held step button", heldStep.holding, false)
assert_eq("disabling a number clears an armed step button", heldStep.armed, false)

-- Field looks: light and dark keep the library's field; slate draws a frame from its field style.
local Umg = require("ModMenu.core.umg")
local Style = require("ModMenu.core.style")
local lightField, lightText, lightSize = Umg.FieldLook({ resolved = Style.Resolve("light"), fontItem = 16 }, nil)
assert_eq("light gives no field style", lightField, nil)
assert_eq("light gives no text style", lightText, nil)
assert_eq("light keeps the config's item size", lightSize, 16)
assert_eq("dark gives no field style", (Umg.FieldLook({ resolved = Style.Resolve("dark"), fontItem = 16 }, nil)), nil)
assert_eq("no resolved theme gives no field style", (Umg.FieldLook({ fontItem = 16 }, nil)), nil)
local slate = Style.Resolve("slate")
local slateField, slateText, slateSize = Umg.FieldLook({ resolved = slate, fontItem = 16, fontScale = 1 }, nil)
assert_eq("slate's field is a frame", slateField and slateField.variant, "frame")
assert_eq("slate's field fill is the resolved field fill", slateField and slateField.fill, slate.field.fill)
assert_eq("slate's field text style is the body", slateText, slate.body)
assert_eq("slate's body size sets the field text size", slateSize, 14)
local looked = Umg.FieldLook({ resolved = slate, fontItem = 16 }, { radius = 2 })
assert_eq("an item look merges into the field", looked and looked.radius, 2)
assert_eq("an item look of stock gives the library's field", (Umg.FieldLook({ resolved = slate, fontItem = 16 }, { variant = "stock" })), nil)
assert_true("a stock field is stock", Umg.IsStockField({ variant = "stock" }))
assert_true("a frame field is not stock", not Umg.IsStockField({ variant = "frame" }))
