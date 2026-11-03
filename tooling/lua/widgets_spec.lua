-- The widget registry must load without UE4SS globals, because the shell requires it at load time.
local okWidgets, Widgets = pcall(require, "ModMenu.widgets.init")
assert_true("widgets.init loads under MoonSharp", okWidgets)
if okWidgets then
    for _, name in ipairs({ "separator", "label", "button", "checkbox", "dropdown", "number", "textinput", "row", "fold" }) do
        assert_true("widgets.init registers " .. name, Widgets.has(name))
    end
end

local Tooltip = require("ModMenu.core.tooltip")

local okNumber, errNumber = pcall(Tooltip.Validate, { tooltip = 3 }, "p")
assert_true("a number tooltip errors", okNumber == false)
assert_true(
    "a number tooltip error names the rule",
    string.find(tostring(errNumber), "p tooltip must be a string", 1, true) ~= nil
)
assert_true("a string tooltip passes", pcall(Tooltip.Validate, { tooltip = "Explains the item" }, "p"))
assert_true("an item without a tooltip passes", pcall(Tooltip.Validate, {}, "p"))
local okTable = pcall(Tooltip.Validate, { tooltip = { "text" } }, "p")
assert_true("a table tooltip errors", okTable == false)
