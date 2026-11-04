-- The spec runs without the game, so it checks validate, the helpers the multiselect exposes, the
-- registry's coercion and a click driven through poll with a fake input.
local Widgets = require("ModMenu.widgets.init")
assert_true("the multiselect type is registered", Widgets.has("multiselect"))
local Multiselect = require("ModMenu.widgets.multiselect")

local abc = { options = { "a", "b", "c" } }

assert_eq("normalize keeps options in option order and drops strangers", Multiselect._normalize({ "c", "a", "z" }, abc), { "a", "c" })
assert_eq("normalize drops duplicates", Multiselect._normalize({ "b", "b", "a" }, abc), { "a", "b" })
assert_eq("normalize of a non-table is empty", Multiselect._normalize("a", abc), {})
assert_eq("normalize of nil is empty", Multiselect._normalize(nil, abc), {})
assert_eq(
    "normalize matches the option value, not the label",
    Multiselect._normalize({ "r" }, { options = { { label = "Red", value = "r" }, "g" } }),
    { "r" }
)

assert_eq("toggle adds an unchecked value in option order", Multiselect._toggle({ "c" }, "a", abc), { "a", "c" })
assert_eq("toggle adds after the existing values", Multiselect._toggle({ "a" }, "b", abc), { "a", "b" })
assert_eq("toggle removes a checked value", Multiselect._toggle({ "a", "b" }, "a", abc), { "b" })
assert_eq("toggle ignores a value that is not an option", Multiselect._toggle({ "a" }, "z", abc), { "a" })
local original = { "a" }
Multiselect._toggle(original, "b", abc)
assert_eq("toggle leaves its input untouched", original, { "a" })

assert_eq("caption marks a checked option", Multiselect._caption("Red", true), "[x] Red")
assert_eq("caption marks an unchecked option", Multiselect._caption("Red", false), "[ ] Red")

local function validateError(extra)
    local item = { id = "m", label = "M", options = { "a", "b", "c" } }
    for key, value in pairs(extra) do
        item[key] = value
    end
    local ok, err = pcall(Multiselect.validate, item, "s", 1)
    return (not ok) and tostring(err) or nil
end

local function says(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a full multiselect item", validateError({ default = { "a", "c" }, columns = 2, onChange = function() end }) == nil)
assert_true("validate accepts an empty default", validateError({ default = {} }) == nil)
assert_true("validate requires an id", says(select(2, pcall(Multiselect.validate, { label = "M", options = { "a" } }, "s", 1)), "requires .id"))
assert_true("validate requires a label", says(select(2, pcall(Multiselect.validate, { id = "m", options = { "a" } }, "s", 1)), "requires .label"))
assert_true("validate requires an options array", says(validateError({ options = "a" }), "multiselect requires an .options array"))
assert_true("validate requires at least one option", says(validateError({ options = {} }), "multiselect requires at least one option"))
assert_true("validate names a default that is not an array", says(validateError({ default = "a" }), "default must be an array"))
assert_true("validate names the options a default may hold", says(validateError({ default = { "a", "z" } }), "default must be one of a, b, c"))
assert_true("validate names a default entry that is not a string", says(validateError({ default = { 1 } }), "default must be one of a, b, c"))
assert_true("validate names columns of zero", says(validateError({ columns = 0 }), "columns must be a number from 1 to 4"))
assert_true("validate names columns of five", says(validateError({ columns = 5 }), "columns must be a number from 1 to 4"))
assert_true("validate names columns that are text", says(validateError({ columns = "2" }), "columns must be a number from 1 to 4"))
assert_true("validate names a columns count that is not whole", says(validateError({ columns = 1.5 }), "columns must be a number from 1 to 4"))
assert_true("validate names onChange", says(validateError({ onChange = 3 }), "onChange must be a function"))
assert_true("validate error carries the section and item prefix", says(validateError({ columns = 0 }), "Register(s) items[1]"))

local values = { ["s.early"] = { "c", "z", "a" } }
Multiselect.seed("s", { id = "m", label = "M", options = { "a", "b", "c" }, default = { "c", "a" } }, values)
assert_eq("seed stores the default in option order", values["s.m"], { "a", "c" })
Multiselect.seed("s", { id = "early", label = "E", options = { "a", "b", "c" } }, values)
assert_eq("seed normalizes a value set before Register", values["s.early"], { "a", "c" })
Multiselect.seed("s", { id = "none", label = "N", options = { "a", "b" } }, values)
assert_eq("seed without a default stores an empty array", values["s.none"], {})
values["s.junk"] = "a"
Multiselect.seed("s", { id = "junk", label = "J", options = { "a", "b" }, default = { "b" } }, values)
assert_eq("seed replaces a value that is not an array with the default", values["s.junk"], { "b" })

-- A fold takes a multiselect and a row does not, because the group's height varies.
local Fold = require("ModMenu.widgets.fold")
local Row = require("ModMenu.widgets.row")
local msItem = { type = "multiselect", id = "m", label = "M", options = { "a", "b" } }
assert_true("a fold accepts a multiselect child", pcall(Fold.validate, { id = "f", label = "F", items = { msItem } }, "s", 1))
local rowOk, rowErr = pcall(Row.validate, { id = "r", items = { msItem } }, "s", 1)
assert_true("a row rejects a multiselect child", rowOk == false and says(tostring(rowErr), "multiselect"))

-- The registry normalizes a multiselect value before it stores it, whether or not the control is built.
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
    sections = {
        {
            id = "s",
            items = {
                { id = "f", type = "fold", label = "F", items = { { id = "m", type = "multiselect", label = "M", options = { "a", "b", "c" }, default = { "b" } } } },
            },
        },
    },
    sectionIndexById = { s = 1 },
    menuOpen = false,
    makeWidgetCtx = function()
        return {}
    end,
}
Registry.Set(unbuilt, "s", "m", { "c", "a", "z" })
assert_eq("Set on an unbuilt multiselect normalizes a table", unbuilt.values["s.m"], { "a", "c" })
Registry.Set(unbuilt, "s", "m", "a")
assert_eq("Set ignores a value that is not a table", unbuilt.values["s.m"], { "a", "c" })
Registry.Set(unbuilt, "s", "m", nil)
assert_eq("Set of nil resets a multiselect to its default", unbuilt.values["s.m"], { "b" })

-- Apply stores the normalized array and never calls onChange.
local calls = 0
local applyItem = { id = "m", label = "M", options = { "a", "b", "c" }, onChange = function()
    calls = calls + 1
end }
local applyCtrl = { kind = "multiselect", item = applyItem, valueKey = "s.m", selected = {}, optionCtrls = {} }
local applyValues = {}
local applyCtx = {
    values = applyValues,
    IsValid = function()
        return true
    end,
}
Multiselect.apply(applyCtrl, { "c", "a", "z" }, applyCtx)
assert_eq("apply stores the normalized array", applyValues["s.m"], { "a", "c" })
assert_eq("apply keeps the selection the poll reads", applyCtrl.selected, { "a", "c" })
assert_eq("apply never calls onChange", calls, 0)

-- A click on an option toggles it, stores the array and fires onChange with the array.
ExecuteInGameThreadWithDelay = function() end
local fired = {}
local clickItem = { id = "m", label = "M", options = { "a", "b", "c" }, onChange = function(v)
    fired[#fired + 1] = v
end }
local clickValues = { ["s.m"] = { "a" } }
local clickCtrl = {
    kind = "multiselect",
    item = clickItem,
    valueKey = "s.m",
    selected = { "a" },
    optionCtrls = {},
}
for _, value in ipairs({ "a", "b", "c" }) do
    clickCtrl.optionCtrls[#clickCtrl.optionCtrls + 1] = {
        kind = "button",
        value = value,
        label = value,
        widget = "w" .. value,
        item = Multiselect._optionItem(clickCtrl, value),
    }
end
local released = {}
local clickCtx = {
    values = clickValues,
    config = {},
    IsValid = function()
        return true
    end,
    SafeCall = function(fn, ...)
        fn(...)
    end,
    ReclaimMenuInput = function() end,
    umg = {
        TrackPointer = function() end,
        SetFillColors = function() end,
        StyleText = function() end,
        SetLabelText = function() end,
    },
    Input = {
        ReleaseClick = function(_, w)
            return released[w] == true
        end,
        DebugClick = function() end,
        SuppressPressEdge = function() end,
        IgnoreClicks = function() end,
    },
}
released.wb = true
Multiselect.poll(clickCtrl, clickCtx)
released.wb = nil
assert_eq("a release over an unchecked option checks it", clickValues["s.m"], { "a", "b" })
assert_eq("a click fires onChange with the array", fired[1], { "a", "b" })
released.wa = true
Multiselect.poll(clickCtrl, clickCtx)
released.wa = nil
assert_eq("a release over a checked option unchecks it", clickValues["s.m"], { "b" })
assert_eq("each click fires onChange once", #fired, 2)
assert_true("a checked option is painted active", clickCtrl.optionCtrls[2].item.active == true)
assert_true("an unchecked option is painted normal", clickCtrl.optionCtrls[1].item.active == false)
Multiselect.poll(clickCtrl, clickCtx)
assert_eq("an idle poll fires nothing", #fired, 2)
