local Options = require("ModMenu.core.options")

local list, labelToValue, valueToLabel = Options.NormalizeOptions({
    "Left",
    { label = "Right", value = "right" },
    { value = "top" },
})

assert_eq("list length", #list, 3)
assert_eq("string option", list[1], { label = "Left", value = "Left" })
assert_eq("label+value option", list[2], { label = "Right", value = "right" })
assert_eq("value-only option", list[3], { label = "top", value = "top" })
assert_eq("order is stable", { list[1].value, list[2].value, list[3].value }, {
    "Left",
    "right",
    "top",
})
assert_eq("labelToValue Right", labelToValue.Right, "right")
assert_eq("valueToLabel right", valueToLabel.right, "Right")

assert_true("filter empty matches", Options.OptionMatchesFilter("Top", "") == true)
assert_true("filter case-insensitive", Options.OptionMatchesFilter("Top", "to") == true)
assert_true("filter miss", Options.OptionMatchesFilter("Top", "bottom") == false)

-- The registry requires the shell build module, which requires UEHelpers from the UE4SS install.
-- The spec host has no UE4SS, so an empty stub stands in; none of the calls below reach it.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Registry = require("ModMenu.shell.registry")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end

-- A closed menu with no live controls, so SetOptions and Set touch only the store.
local function makeState(items)
    return {
        values = {},
        liveControls = {},
        sections = { { id = "s", items = items } },
        sectionIndexById = { s = 1 },
        menuOpen = false,
        makeWidgetCtx = function()
            return {}
        end,
    }
end

local emptyList = Options.NormalizeOptions({})
assert_eq("SetOptions with an empty list clears the value: normalize returns an empty list", emptyList, {})

local S = makeState({ { id = "d", type = "dropdown", options = { "a", "b" }, default = "a" } })
S.values["s.d"] = "a"
local ok, err = pcall(Registry.SetOptions, S, "s", "d", {}, false)
assert_true("SetOptions with an empty list clears the value: no error", ok == true)
if not ok then
    assert_eq("SetOptions with an empty list clears the value: error text", tostring(err), nil)
end
assert_eq("SetOptions with an empty list clears the value: value is nil", S.values["s.d"], nil)
assert_eq("SetOptions with an empty list clears the value: options are empty", S.sections[1].items[1].options, {})
assert_true(
    "SetOptions still rejects a non-table options value",
    pcall(Registry.SetOptions, S, "s", "d", "a") == false
)

local N = makeState({ { id = "n", type = "number", min = 0, max = 10, default = 3 } })
Registry.Set(N, "s", "n", "5")
assert_eq("Set on a number item coerces text and ignores non-numbers: text becomes a number", N.values["s.n"], 5)
Registry.Set(N, "s", "n", "abc")
assert_eq("Set on a number item coerces text and ignores non-numbers: non-number keeps 5", N.values["s.n"], 5)
Registry.Set(N, "s", "n", 7)
assert_eq("Set on a number item stores a number argument unchanged", N.values["s.n"], 7)

local N2 = makeState({ { id = "n", type = "number", min = 0, max = 10, default = 3 } })
Registry.Set(N2, "s", "n", 99)
assert_eq("Set on a number item clamps a number above max to max", N2.values["s.n"], 10)

local Dropdown = require("ModMenu.widgets.dropdown")
assert_true(
    "dropdown validate accepts an empty options array",
    pcall(Dropdown.validate, { id = "d", label = "D", options = {} }, "s", 1) == true
)
assert_true(
    "dropdown validate still rejects a missing options array",
    pcall(Dropdown.validate, { id = "d", label = "D" }, "s", 1) == false
)

-- The README's "swap which controls exist" pattern registers the same section table again,
-- after SetOptions has written the empty list into that table's dropdown item.
local R = {
    values = {},
    liveControls = {},
    sections = {},
    sectionIndexById = {},
    collapsedById = {},
    config = {},
    menuOpen = false,
    makeWidgetCtx = function()
        return {}
    end,
}
local section = { id = "r", items = { { id = "d", type = "dropdown", label = "D", options = { "a" } } } }
Registry.Register(R, section)
Registry.SetOptions(R, "r", "d", {})
local reOk, reErr = pcall(Registry.Register, R, section)
assert_true("Register again after SetOptions with an empty list does not error", reOk == true)
if not reOk then
    assert_eq("Register again after SetOptions with an empty list: error text", tostring(reErr), nil)
end
