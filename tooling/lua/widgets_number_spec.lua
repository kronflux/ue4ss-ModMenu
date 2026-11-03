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

-- The stub ctx carries only the fields apply reads, so no UE4SS global is needed.
-- SetText fails on the missing FText global inside apply's pcall, which apply already tolerates.
local calls = 0
local seen = nil
item.onChange = function(v)
    calls = calls + 1
    seen = v
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
Number.apply(ctrl, "abc", ctx)
assert_eq("apply with a numeric string then junk keeps the number", values["s.n"], 5)
assert_eq("onChange runs once for the numeric string", calls, 1)
assert_eq("onChange receives a number", type(seen), "number")
