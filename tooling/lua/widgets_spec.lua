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

-- Toggle variants: light and dark keep the stock checkbox, every other theme draws its own toggle.
local Style = require("ModMenu.core.style")
local Checkbox = require("ModMenu.widgets.checkbox")
local desktopCtx = { Input = { IsTouch = function() return false end } }
local touchCtx = { Input = { IsTouch = function() return true end } }
assert_true("light draws the stock toggle", Checkbox.Variant(Style.Resolve("light"), desktopCtx) == "stock")
assert_true("dark draws the stock toggle", Checkbox.Variant(Style.Resolve("dark"), desktopCtx) == "stock")
assert_true("slate draws a switch", Checkbox.Variant(Style.Resolve("slate"), desktopCtx) == "switch")
assert_true("slate draws a switch in touch mode", Checkbox.Variant(Style.Resolve("slate"), touchCtx) == "switch")
assert_true("light stays stock in touch mode", Checkbox.Variant(Style.Resolve("light"), touchCtx) == "stock")
local checkTheme = Style.Resolve({ name = "Mine", base = "slate", toggle = { variant = "check" } })
assert_true("a custom definition with a check toggle draws a check", Checkbox.Variant(checkTheme, desktopCtx) == "check")
assert_true("no resolved style draws the stock toggle", Checkbox.Variant(nil, desktopCtx) == "stock")
-- A host's toggle override takes effect on light and dark too, because an explicit style always shows.
assert_true("light with a slate toggle override draws a switch", Checkbox.Variant(Style.Resolve("light", { toggle = "slate" }), desktopCtx) == "switch")
assert_true("dark with a check toggle override draws a check", Checkbox.Variant(Style.Resolve("dark", { toggle = { variant = "check" } }), desktopCtx) == "check")

-- Toggle sizes follow the text's touch multiplier, so the control keeps its proportion to its label.
assert_true("a desktop toggle keeps its size", Checkbox.Scale({ pointerMode = "mouse" }) == 1)
assert_true("a touch toggle scales by the default touch multiplier", Checkbox.Scale({ pointerMode = "touch" }) == 1.75)
assert_true("a touch toggle scales by touchFontScale", Checkbox.Scale({ pointerMode = "touch", touchFontScale = 2 }) == 2)

-- A box or chip radius derived as h / 2 becomes 3, also after an item look changed h.
local slateToggle = Style.Resolve("slate").toggle
local lookToggle = Style.ForItem(Style.Resolve("slate"), "toggle", { h = 24 })
assert_true("a derived toggle radius gives a box radius of 3", Checkbox._boxRadius(slateToggle, slateToggle.h) == 3)
assert_true("a look that changes h still gives a box radius of 3", Checkbox._boxRadius(lookToggle, slateToggle.h) == 3)
assert_true("an explicit toggle radius is kept", Checkbox._boxRadius({ radius = 5, h = 20 }, 20) == 5)

-- Disabling a themed toggle shows its normal look; the stock toggle is left alone.
local shown = {}
local fakePaint = { ShowState = function(ctrl, state) shown[#shown + 1] = { ctrl = ctrl, state = state } end }
local shapedCtrl = { shaped = true, paint = {} }
Checkbox.onItemState(shapedCtrl, false, true, { paint = fakePaint })
assert_true("disabling a themed toggle shows its normal look", #shown == 1 and shown[1].state == "normal"
    and shown[1].ctrl == shapedCtrl.paint)
Checkbox.onItemState(shapedCtrl, true, true, { paint = fakePaint })
assert_true("enabling a themed toggle leaves its look to the poll", #shown == 1)
Checkbox.onItemState({ asButton = true, paint = {} }, false, true, { paint = fakePaint })
assert_true("disabling a stock toggle changes nothing", #shown == 1)
