-- The spec runs without the game, so it checks validate, the helpers the colour picker exposes, the
-- registry's coercion and a drag driven through poll with fake sliders.
local Widgets = require("ModMenu.widgets.init")
assert_true("the colorpicker type is registered", Widgets.has("colorpicker"))
local Colorpicker = require("ModMenu.widgets.colorpicker")

assert_eq(
    "coerce clamps every channel to 0..1",
    Colorpicker._coerce({ R = 2, G = -1, B = 0.5, A = 0.5 }, { alpha = true }),
    { R = 1, G = 0, B = 0.5, A = 0.5 }
)
assert_eq("coerce keeps A at 1 when alpha is false", Colorpicker._coerce({ R = 0, G = 0, B = 0, A = 0.2 }, { alpha = false }).A, 1)
assert_eq("coerce gives A 1 when A is missing", Colorpicker._coerce({ R = 0.1, G = 0.2, B = 0.3 }, {}).A, 1)
assert_eq("coerce treats alpha as on when it is not set", Colorpicker._coerce({ R = 0, G = 0, B = 0, A = 0.25 }, {}).A, 0.25)
assert_eq("coerce gives 0 to a missing colour channel", Colorpicker._coerce({ R = 1 }, {}), { R = 1, G = 0, B = 0, A = 1 })
assert_eq("coerce of a string is nil", Colorpicker._coerce("red", {}), nil)
assert_eq("coerce of nil is nil", Colorpicker._coerce(nil, {}), nil)
local input = { R = 0.5, G = 0.5, B = 0.5, A = 0.5 }
local copy = Colorpicker._coerce(input, {})
copy.R = 0
assert_eq("coerce returns a copy", input.R, 0.5)

assert_eq("three sliders when alpha is false", Colorpicker._channels({ alpha = false }), { "R", "G", "B" })
assert_eq("four sliders by default", Colorpicker._channels({}), { "R", "G", "B", "A" })
assert_eq("snap rounds to a hundredth", Colorpicker._snap(0.456), 0.46)
assert_eq("snap clamps above one", Colorpicker._snap(1.4), 1)
assert_eq("snap clamps below zero", Colorpicker._snap(-0.2), 0)
assert_eq("format shows two decimals", Colorpicker._format(0.5), "0.50")

local function validateError(extra)
    local item = { id = "c", label = "C", default = { R = 1, G = 0.5, B = 0, A = 1 } }
    for key, value in pairs(extra) do
        if value == "__nil" then
            item[key] = nil
        else
            item[key] = value
        end
    end
    local ok, err = pcall(Colorpicker.validate, item, "s", 1)
    return (not ok) and tostring(err) or nil
end

local function says(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("validate accepts a full item", validateError({ alpha = false, onChange = function() end, tooltip = "t" }) == nil)
assert_true("validate accepts an item with no default", validateError({ default = "__nil" }) == nil)
assert_true("validate requires an id", says(select(2, pcall(Colorpicker.validate, { label = "C" }, "s", 1)), "requires .id"))
assert_true("validate requires a label", says(select(2, pcall(Colorpicker.validate, { id = "c" }, "s", 1)), "requires .label"))
assert_true("validate names a default that is not a table", says(validateError({ default = "red" }), "default must be a table with R, G, B and A"))
assert_true("validate names a default with a missing channel", says(validateError({ default = { R = 1, G = 1, B = 1 } }), "default must be a table with R, G, B and A"))
assert_true("validate names the channel that is not a number", says(validateError({ default = { R = 1, G = "x", B = 1, A = 1 } }), "default.G must be a number from 0 to 1"))
assert_true("validate names the channel above one", says(validateError({ default = { R = 1.5, G = 1, B = 1, A = 1 } }), "default.R must be a number from 0 to 1"))
assert_true("validate names the channel below zero", says(validateError({ default = { R = 1, G = 1, B = -0.1, A = 1 } }), "default.B must be a number from 0 to 1"))
assert_true("validate names the alpha channel", says(validateError({ default = { R = 1, G = 1, B = 1, A = 2 } }), "default.A must be a number from 0 to 1"))
assert_true("validate names alpha that is not a boolean", says(validateError({ alpha = "no" }), "alpha must be a boolean"))
assert_true("validate names onChange", says(validateError({ onChange = 3 }), "onChange must be a function"))
assert_true("validate error carries the section and item prefix", says(validateError({ alpha = 1 }), "Register(s) items[1]"))

local values = { ["s.early"] = { R = 3, G = 0, B = 0, A = 1 } }
Colorpicker.seed("s", { id = "c", label = "C", default = { R = 0.1, G = 0.2, B = 0.3, A = 0.4 } }, values)
assert_eq("seed stores the default", values["s.c"], { R = 0.1, G = 0.2, B = 0.3, A = 0.4 })
Colorpicker.seed("s", { id = "early", label = "E" }, values)
assert_eq("seed coerces a value set before Register", values["s.early"], { R = 1, G = 0, B = 0, A = 1 })
Colorpicker.seed("s", { id = "none", label = "N" }, values)
assert_eq("seed without a default stores opaque white", values["s.none"], { R = 1, G = 1, B = 1, A = 1 })
values["s.junk"] = "red"
Colorpicker.seed("s", { id = "junk", label = "J", default = { R = 0, G = 0, B = 0, A = 1 } }, values)
assert_eq("seed replaces a value that is not a table with the default", values["s.junk"], { R = 0, G = 0, B = 0, A = 1 })

-- A fold takes a colorpicker and a row does not, because the group's height varies.
local Fold = require("ModMenu.widgets.fold")
local Row = require("ModMenu.widgets.row")
local cpItem = { type = "colorpicker", id = "c", label = "C" }
assert_true("a fold accepts a colorpicker child", pcall(Fold.validate, { id = "f", label = "F", items = { cpItem } }, "s", 1))
local rowOk, rowErr = pcall(Row.validate, { id = "r", items = { cpItem } }, "s", 1)
assert_true("a row rejects a colorpicker child", rowOk == false and says(tostring(rowErr), "colorpicker"))

-- The registry coerces a colour before it stores it, whether or not the control is built.
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
                { id = "f", type = "fold", label = "F", items = { { id = "c", type = "colorpicker", label = "C", alpha = false, default = { R = 0, G = 1, B = 0, A = 1 } } } },
            },
        },
    },
    sectionIndexById = { s = 1 },
    menuOpen = false,
    makeWidgetCtx = function()
        return {}
    end,
}
Registry.Set(unbuilt, "s", "c", { R = 2, G = 0.5, B = -1, A = 0.3 })
assert_eq("Set on an unbuilt colorpicker clamps and drops alpha", unbuilt.values["s.c"], { R = 1, G = 0.5, B = 0, A = 1 })
Registry.Set(unbuilt, "s", "c", "red")
assert_eq("Set ignores a value that is not a table", unbuilt.values["s.c"], { R = 1, G = 0.5, B = 0, A = 1 })
Registry.Set(unbuilt, "s", "c", nil)
assert_eq("Set of nil resets a colorpicker to its default", unbuilt.values["s.c"], { R = 0, G = 1, B = 0, A = 1 })

local function FakeSlider(v)
    return {
        v = v,
        captured = false,
        GetValue = function(self)
            return self.v
        end,
        SetValue = function(self, n)
            self.v = n
        end,
        HasMouseCapture = function(self)
            return self.captured
        end,
    }
end

-- Apply stores the coerced colour, paints the swatch and the sliders, and never calls onChange.
local calls = 0
local applyItem = { id = "c", label = "C", onChange = function()
    calls = calls + 1
end }
local swatchColor = nil
local applyCtrl = {
    kind = "colorpicker",
    item = applyItem,
    valueKey = "s.c",
    value = { R = 1, G = 1, B = 1, A = 1 },
    lastFired = { R = 1, G = 1, B = 1, A = 1 },
    swatch = { SetBrushColor = function(_, color)
        swatchColor = color
    end },
    channels = {},
}
for _, key in ipairs({ "R", "G", "B", "A" }) do
    applyCtrl.channels[#applyCtrl.channels + 1] = { key = key, slider = FakeSlider(1), valueText = {}, engineValue = 1 }
end
local applyValues = {}
local applyCtx = {
    values = applyValues,
    IsValid = function()
        return true
    end,
}
Colorpicker.apply(applyCtrl, { R = 0.25, G = 2, B = 0, A = 0.5 }, applyCtx)
assert_eq("apply stores the clamped colour", applyValues["s.c"], { R = 0.25, G = 1, B = 0, A = 0.5 })
assert_eq("apply paints the swatch", swatchColor, { R = 0.25, G = 1, B = 0, A = 0.5 })
assert_eq("apply moves the red slider", applyCtrl.channels[1].slider.v, 0.25)
assert_eq("apply never calls onChange", calls, 0)
applyValues["s.c"] = "junk"
Colorpicker.apply(applyCtrl, "junk", applyCtx)
assert_eq("apply with junk puts the last good colour back in the store", applyValues["s.c"], { R = 0.25, G = 1, B = 0, A = 0.5 })

-- A drag moves the stored colour and the swatch at once, and onChange fires once when the mouse is released.
local fired = {}
local dragItem = { id = "c", label = "C", onChange = function(color)
    fired[#fired + 1] = color
end }
local dragSwatch = nil
local dragCtrl = {
    kind = "colorpicker",
    item = dragItem,
    valueKey = "s.c",
    value = { R = 0.5, G = 0.5, B = 0.5, A = 1 },
    lastFired = { R = 0.5, G = 0.5, B = 0.5, A = 1 },
    swatch = { SetBrushColor = function(_, color)
        dragSwatch = color
    end },
    channels = {},
}
for _, key in ipairs({ "R", "G", "B", "A" }) do
    dragCtrl.channels[#dragCtrl.channels + 1] = {
        key = key,
        slider = FakeSlider(key == "A" and 1 or 0.5),
        valueText = {},
        engineValue = key == "A" and 1 or 0.5,
    }
end
local dragValues = { ["s.c"] = { R = 0.5, G = 0.5, B = 0.5, A = 1 } }
local reclaimed = 0
local dragCtx = {
    values = dragValues,
    IsValid = function()
        return true
    end,
    SafeCall = function(fn, ...)
        fn(...)
    end,
    ReclaimMenuInput = function()
        reclaimed = reclaimed + 1
    end,
}
local green = dragCtrl.channels[2]
green.slider.captured = true
green.slider.v = 0.456
Colorpicker.poll(dragCtrl, dragCtx)
assert_eq("a drag stores the snapped channel", dragValues["s.c"].G, 0.46)
assert_eq("a drag keeps the other channels", dragValues["s.c"].R, 0.5)
assert_eq("a drag repaints the swatch", dragSwatch, { R = 0.5, G = 0.46, B = 0.5, A = 1 })
assert_eq("onChange does not fire while the mouse is held", #fired, 0)
green.slider.v = 0.8
Colorpicker.poll(dragCtrl, dragCtx)
assert_eq("a later poll in the same drag follows the slider", dragValues["s.c"].G, 0.8)
assert_eq("still nothing fired mid-drag", #fired, 0)
green.slider.captured = false
Colorpicker.poll(dragCtrl, dragCtx)
assert_eq("onChange fires once at the end of the drag", #fired, 1)
assert_eq("onChange receives the colour", fired[1], { R = 0.5, G = 0.8, B = 0.5, A = 1 })
assert_eq("the menu input is reclaimed after the drag", reclaimed, 1)
fired[1].R = 0
assert_eq("onChange receives a copy, not the stored colour", dragValues["s.c"].R, 0.5)
Colorpicker.poll(dragCtrl, dragCtx)
assert_eq("an idle poll fires nothing", #fired, 1)

-- The engine slider holds a single-precision float, so it reads back a value a host wrote with a
-- tiny error. That read-back is not a drag: an off-grid host colour must stay as written and fire nothing.
Colorpicker.apply(dragCtrl, { R = 0.737, G = 0.8, B = 0.5, A = 1 }, dragCtx)
local red = dragCtrl.channels[1]
red.slider.v = 0.737 + 1e-8
Colorpicker.poll(dragCtrl, dragCtx)
assert_eq("a float read-back keeps an off-grid host colour", dragValues["s.c"].R, 0.737)
assert_eq("a float read-back fires nothing", #fired, 1)

-- A poll on a widget that is gone does nothing.
local goneCtx = {
    values = dragValues,
    IsValid = function()
        return false
    end,
}
assert_true("poll tolerates an invalid widget", pcall(Colorpicker.poll, dragCtrl, goneCtx))

-- Themed channel bars keep each colour channel's hue so the sliders read at a glance; alpha takes the slider track.
local track = { R = 0.2, G = 0.2, B = 0.2, A = 1 }
local redBar = Colorpicker._channelBar("R", { track = track })
assert_true("the red channel bar is red", redBar.R > redBar.G and redBar.R > redBar.B)
assert_eq("the alpha channel bar takes the slider track", Colorpicker._channelBar("A", { track = track }), track)

-- A picker's look styles its channel sliders, so it merges over the theme's slider style.
local StyleForPicker = require("ModMenu.core.style")
local slatePicker = StyleForPicker.Resolve("slate")
assert_eq("a picker look reaches the channel slider style", Colorpicker._sliderLook(slatePicker, { look = { thickness = 8 } }).thickness, 8)
assert_eq("a picker without a look keeps the theme's slider thickness", Colorpicker._sliderLook(slatePicker, {}).thickness, slatePicker.slider.thickness)
assert_eq("a picker with no theme has an empty slider style", next(Colorpicker._sliderLook(nil, {})), nil)
