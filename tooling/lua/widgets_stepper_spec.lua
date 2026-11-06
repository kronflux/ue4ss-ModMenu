-- The spec runs without the game, so it checks validate and the helpers the stepper exposes.
local Widgets = require("ModMenu.widgets.init")
assert_true("the stepper type is registered", Widgets.has("stepper"))
local Stepper = require("ModMenu.widgets.stepper")

assert_eq("coerce snaps to the nearest step", Stepper._coerce(7.3, { min = 0, max = 10, step = 0.5 }), 7.5)
assert_eq("coerce rejects a non-numeric string", Stepper._coerce("x", { min = 0, max = 10, step = 0.5 }), nil)
assert_eq("coerce clamps above max", Stepper._coerce(40, { min = 0, max = 10 }), 10)
assert_eq("coerce clamps below min", Stepper._coerce(-4, { min = 0, max = 10 }), 0)
assert_eq("coerce snaps from min, not from zero", Stepper._coerce(2.2, { min = 1, max = 9, step = 2 }), 3)
assert_eq("coerce rounds an integer item", Stepper._coerce(2.5, { min = 0, max = 10, integer = true }), 3)
assert_eq("coerce reads a numeric string", Stepper._coerce("4", { min = 0, max = 10 }), 4)
assert_eq("coerce of nil gives the default", Stepper._coerce(nil, { min = 0, max = 10, default = 4 }), 4)
assert_eq("coerce of nil without a default gives min", Stepper._coerce(nil, { min = 2, max = 10 }), 2)
assert_eq("coerce of nil without min or default gives zero", Stepper._coerce(nil, {}), 0)
assert_eq("coerce without a range keeps the value", Stepper._coerce(-7, { step = 1 }), -7)

local range = { min = 0, max = 10, step = 1 }
assert_eq("next moves one step up", Stepper._next(4, 1, range), 5)
assert_eq("next moves one step down", Stepper._next(4, -1, range), 3)
assert_eq("next stops at max", Stepper._next(10, 1, range), 10)
assert_eq("next stops at min", Stepper._next(0, -1, range), 0)
assert_eq("next uses a step of one when the item has none", Stepper._next(2, 1, { min = 0, max = 10 }), 3)
assert_eq("next from max off the step grid goes to the grid point below", Stepper._next(10, -1, { min = 0, max = 10, step = 3 }), 9)
assert_eq("next to the end of an uneven range reaches max", Stepper._next(9, 1, { min = 0, max = 10, step = 3 }), 10)
assert_eq("next keeps decimal steps free of float noise", Stepper._next(0.2, 1, { min = 0, max = 1, step = 0.1 }), 0.3)

assert_eq("format uses %d for an integer item", Stepper._format(3, { integer = true }), "3")
assert_eq("format uses %g for any other item", Stepper._format(7.5, {}), "7.5")
assert_eq("format drops trailing zeros under %g", Stepper._format(2, {}), "2")
assert_eq("format uses a format string", Stepper._format(0.25, { format = "%.2f" }), "0.25")
assert_eq("format falls back when the format string fails", Stepper._format(2, { format = "%q%q" }), "2")

assert_eq("repeat is not due before 400 ms", Stepper._repeat(399, 0), false)
assert_eq("repeat is due at 400 ms", Stepper._repeat(400, 0), true)
assert_eq("repeat is not due 50 ms after a step", Stepper._repeat(450, 400), false)
assert_eq("repeat is due 100 ms after a step", Stepper._repeat(500, 400), true)

local function validateError(extra)
    local item = { id = "v", label = "V", min = 0, max = 10 }
    for key, value in pairs(extra) do
        item[key] = value
    end
    local ok, err = pcall(Stepper.validate, item, "s", 1)
    return (not ok) and tostring(err) or nil
end

local function says(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a full stepper item", validateError({ step = 0.5, default = 3, integer = false, format = "%.1f", onChange = function() end }) == nil)
assert_true("validate accepts a stepper without a range", pcall(Stepper.validate, { id = "v", label = "V" }, "s", 1))
assert_true("validate requires an id", says(select(2, pcall(Stepper.validate, { label = "V" }, "s", 1)), "requires .id"))
assert_true("validate requires a label", says(select(2, pcall(Stepper.validate, { id = "v" }, "s", 1)), "requires .label"))
assert_true("validate names min", says(validateError({ min = "a" }), "min must be a number"))
assert_true("validate names max", says(validateError({ max = "a" }), "max must be a number"))
assert_true("validate names an inverted range", says(validateError({ min = 5, max = 5 }), "min must be less than max"))
assert_true("validate names a zero step", says(validateError({ step = 0 }), "step must be a positive number"))
assert_true("validate names a text step", says(validateError({ step = "a" }), "step must be a positive number"))
assert_true("validate names a default that is not numeric", says(validateError({ default = "loud" }), "default must be numeric"))
assert_true("validate names integer", says(validateError({ integer = "yes" }), "integer must be a boolean"))
assert_true("validate names format", says(validateError({ format = 3 }), "format must be a string"))
assert_true("validate names onChange", says(validateError({ onChange = 3 }), "onChange must be a function"))
assert_true("validate error carries the section and item prefix", says(validateError({ min = "a" }), "Register(s) items[1]"))

local values = { ["s.early"] = "12" }
local good = { id = "v", label = "V", min = 0, max = 10, default = 5 }
Stepper.seed("s", good, values)
assert_eq("seed stores the default", values["s.v"], 5)
Stepper.seed("s", { id = "early", label = "E", min = 0, max = 10 }, values)
assert_eq("seed coerces a value set before Register", values["s.early"], 10)

-- The registry coerces a stepper value before it stores it, whether or not the control is built.
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
    sections = { { id = "s", items = { { id = "v", type = "stepper", label = "V", min = 0, max = 10, step = 0.5, default = 2 } } } },
    sectionIndexById = { s = 1 },
    menuOpen = false,
    makeWidgetCtx = function()
        return {}
    end,
}
Registry.Set(unbuilt, "s", "v", "7.3")
assert_eq("Set on an unbuilt stepper snaps text to the step", unbuilt.values["s.v"], 7.5)
Registry.Set(unbuilt, "s", "v", 99)
assert_eq("Set on an unbuilt stepper clamps to max", unbuilt.values["s.v"], 10)
Registry.Set(unbuilt, "s", "v", "abc")
assert_eq("Set on an unbuilt stepper ignores a value that is not a number", unbuilt.values["s.v"], 10)
Registry.Set(unbuilt, "s", "v", nil)
assert_eq("Set of nil resets a stepper to its default", unbuilt.values["s.v"], 2)

-- The stub ctx carries only the fields apply reads. Painting fails on the missing FText global inside a pcall.
local calls = 0
local item = { id = "v", label = "V", min = 0, max = 10, step = 0.5, onChange = function()
    calls = calls + 1
end }
local ctrl = { kind = "stepper", item = item, valueKey = "s.v", value = 2 }
local ctx = {
    values = values,
    IsValid = function(o)
        return o ~= nil
    end,
}
Stepper.apply(ctrl, "7.3", ctx)
assert_eq("apply coerces and stores the value", values["s.v"], 7.5)
values["s.v"] = "abc"
Stepper.apply(ctrl, "abc", ctx)
assert_eq("apply with junk puts the last good value back in the store", values["s.v"], 7.5)
assert_eq("apply never calls onChange", calls, 0)

-- A click moves one step and fires onChange. The held-button repeat is driven by a fake clock.
local fired = {}
local clickItem = { id = "v", label = "V", min = 0, max = 10, step = 1, onChange = function(v)
    fired[#fired + 1] = v
end }
local clickValues = { ["s.v"] = 5 }
local clickCtrl = {
    kind = "stepper",
    item = clickItem,
    valueKey = "s.v",
    value = 5,
    buttons = { { dir = -1, widget = "minus" }, { dir = 1, widget = "plus" } },
}
local down, clickNow = {}, 0
local released = {}
local reclaims = 0
local clickCtx = {
    values = clickValues,
    IsValid = function()
        return true
    end,
    SafeCall = function(fn, ...)
        fn(...)
    end,
    ReclaimMenuInput = function()
        reclaims = reclaims + 1
    end,
    umg = { TrackPointer = function() end },
    Input = {
        WidgetIsDown = function(w)
            return down[w] == true
        end,
        ReleaseClick = function(_, w)
            return released[w] == true
        end,
        SuppressPressEdge = function() end,
        IgnoreClicks = function() end,
    },
}
Stepper._clock = function()
    return clickNow
end
Stepper.poll(clickCtrl, clickCtx)
released.plus = true
Stepper.poll(clickCtrl, clickCtx)
released.plus = nil
assert_eq("a release over plus moves one step up", clickValues["s.v"], 6)
assert_eq("a release fires onChange with the new value", fired[1], 6)
assert_eq("a click reclaims the menu input once", reclaims, 1)

down.minus = true
clickNow = 0
Stepper.poll(clickCtrl, clickCtx)
clickNow = 0.3
Stepper.poll(clickCtrl, clickCtx)
assert_eq("holding for 300 ms does not repeat", clickValues["s.v"], 6)
clickNow = 0.4
Stepper.poll(clickCtrl, clickCtx)
assert_eq("holding for 400 ms repeats once", clickValues["s.v"], 5)
clickNow = 0.45
Stepper.poll(clickCtrl, clickCtx)
assert_eq("a repeat waits 100 ms for the next one", clickValues["s.v"], 5)
clickNow = 0.5
Stepper.poll(clickCtrl, clickCtx)
assert_eq("a repeat comes every 100 ms", clickValues["s.v"], 4)
-- Reclaiming the menu input resets the engine's input mode and cancels a held press,
-- so a repeat must not do it.
assert_eq("a repeat does not reclaim the menu input while the button is held", reclaims, 1)
down.minus = nil
released.minus = true
clickNow = 0.52
Stepper.poll(clickCtrl, clickCtx)
released.minus = nil
assert_eq("the release after a repeat adds no extra step", clickValues["s.v"], 4)
assert_eq("the end of a run of repeats reclaims the menu input once", reclaims, 2)
assert_eq("each repeat fired onChange", #fired, 3)

clickValues["s.v"] = 10
released.plus = true
Stepper.poll(clickCtrl, clickCtx)
released.plus = nil
assert_eq("a click at max changes nothing", clickValues["s.v"], 10)
assert_eq("a click at max does not fire onChange", #fired, 3)
-- Disabling the stepper in the middle of a hold drops the press and reclaims the input the repeats left alone.
local stubbedStepperHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedStepperHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local StepperInput = require("ModMenu.core.input")
if stubbedStepperHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
local heldButton = { dir = 1, widget = "plus", holding = true, armed = true, downAt = 0, lastStepMs = 500, repeated = true }
local heldCtrl = { kind = "stepper", item = clickItem, valueKey = "s.v", buttons = { heldButton } }
local heldReclaims = 0
local heldCtx = {
    Input = StepperInput,
    ReclaimMenuInput = function()
        heldReclaims = heldReclaims + 1
    end,
}
Stepper.onItemState(heldCtrl, false, true, heldCtx)
assert_eq("disabling mid-hold clears the hold start", heldButton.downAt, nil)
assert_eq("disabling mid-hold ends the run of repeats", heldButton.repeated, false)
assert_eq("disabling mid-hold clears holding", heldButton.holding, false)
assert_eq("disabling mid-hold reclaims the menu input once", heldReclaims, 1)
Stepper.onItemState(heldCtrl, true, true, heldCtx)
assert_eq("enabling the stepper reclaims nothing", heldReclaims, 1)
Stepper._clock = os.clock

-- The stepper's minus and plus buttons take the stepper fields over the button style.
local Style = require("ModMenu.core.style")
local Paint = require("ModMenu.core.paint")
local slateSteps = Stepper._states(Style.Resolve("slate"), {})
assert_eq("slate stepper buttons follow the button radius", slateSteps.normal.radius, 8)
local squareSteps = Stepper._states(Style.Resolve({ base = "slate", stepper = { radius = 0, role = "primary" } }), {})
assert_eq("a stepper radius wins over the button radius", squareSteps.normal.radius, 0)
local slatePrimary = Style.Resolve("slate").button.roles.primary.fill
assert_eq("the stepper role picks the button role", squareSteps.normal.fill, slatePrimary)
local lookSteps = Stepper._states(Style.Resolve("slate"), { look = { pill = true } })
assert_eq("an item look on the stepper reaches its buttons", lookSteps.normal.pill, true)
local lightSteps = Stepper._states(Style.Resolve("light"), {})
assert_true("light stepper buttons keep the legacy recoloured button", Paint.NeedsShapes(lightSteps) == false)
assert_eq("light stepper buttons rest on the legacy buttonBg", lightSteps.normal.fill,
    require("ModMenu.core.theme").Preset("light").buttonBg)
