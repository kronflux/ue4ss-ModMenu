-- The widget registry must load without UE4SS globals, because the shell requires it at load time.
local okWidgets, Widgets = pcall(require, "ModMenu.widgets.init")
assert_true("widgets.init loads under MoonSharp", okWidgets)
if okWidgets then
    for _, name in ipairs({ "separator", "label", "button", "checkbox", "dropdown", "number", "textinput", "row", "fold" }) do
        assert_true("widgets.init registers " .. name, Widgets.has(name))
    end
    assert_true("widgets.init registers slider", Widgets.has("slider"))
    assert_true("widgets.init registers radio", Widgets.has("radio"))
    assert_true("widgets.init registers keybind", Widgets.has("keybind"))

    -- The builder's row and fold child lists carry the new types, so the Lua lists must accept the same children.
    local Row = Widgets.get("row")
    local Fold = Widgets.get("fold")
    local slider = { type = "slider", id = "s", label = "S", min = 0, max = 10 }
    local radio = { type = "radio", id = "r", label = "R", options = { "a", "b" } }
    local keybind = { type = "keybind", id = "k", label = "K" }
    assert_true("row accepts a slider child", pcall(Row.validate, { type = "row", items = { slider } }, "sec", 1))
    local okRowRadio, errRowRadio = pcall(Row.validate, { type = "row", items = { radio } }, "sec", 1)
    assert_true("row rejects a radio child", okRowRadio == false)
    assert_true(
        "row rejection names the allowed list",
        string.find(tostring(errRowRadio), "slider", 1, true) ~= nil
    )
    assert_true(
        "fold accepts slider, radio and keybind children",
        pcall(Fold.validate, { type = "fold", id = "f", label = "F", items = { slider, radio, keybind } }, "sec", 1)
    )
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
