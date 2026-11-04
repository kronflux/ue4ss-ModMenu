-- The button widget is tested through Button.poll and Button.pollClick with a fake pointer, because
-- building the UMG widgets needs the engine, which MoonSharp does not have. A mouse click fires when
-- the pointer is released over the button, and a touch tap fires on the press edge.
local okButton, Button = pcall(require, "ModMenu.widgets.button")
assert_true("widgets.button loads under MoonSharp", okButton)
if not okButton then
    return
end

-- FireClick schedules a delayed re-claim of the menu input; the spec has no game thread to run it.
ExecuteInGameThreadWithDelay = function() end

-- Input requires UEHelpers at load, so an empty stub stands in when no earlier spec loaded it.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okInput, Input = pcall(require, "ModMenu.core.input")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("core.input loads under MoonSharp", okInput)
if not okInput then
    return
end

--- A pointer the spec drives by setting fields; the fake widget reports them to the real Input.
local function newPointer(touch)
    return { down = false, hovered = true, touch = touch == true }
end

local function newWidget(pointer)
    local widget = {}
    function widget:IsPressed()
        return pointer.down
    end
    function widget:HasMouseCapture()
        return pointer.down
    end
    function widget:IsHovered()
        return pointer.hovered
    end
    return widget
end

local function newContext()
    return {
        Input = Input,
        umg = { TrackPointer = function() end },
        SafeCall = function(fn)
            fn()
        end,
        ReclaimMenuInput = function() end,
    }
end

local function newControl(pointer, clicks)
    return {
        kind = "button",
        widget = newWidget(pointer),
        item = {
            id = "b",
            variant = "default",
            onClick = function()
                clicks.count = clicks.count + 1
            end,
        },
    }
end
local function setup(touch)
    local clicks = { count = 0 }
    local pointer = newPointer(touch)
    Input.SetPointerMode(touch and "touch" or "mouse")
    return newControl(pointer, clicks), newContext(), pointer, clicks
end

-- A press then a release over the button is one click, and it lands on the release tick.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    assert_eq("a held mouse button fires no click while it is down", clicks.count, 0)
    pointer.down = false
    Button.poll(ctrl, ctx)
    assert_eq("a release over the button fires one click", clicks.count, 1)
    Button.poll(ctrl, ctx)
    assert_eq("the next idle poll fires no second click", clicks.count, 1)
end

-- A release after the pointer left the button cancels the click.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    pointer.hovered = false
    pointer.down = false
    Button.poll(ctrl, ctx)
    assert_eq("a release off the button fires no click", clicks.count, 0)
end

-- A press that never ends has not clicked yet.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    pointer.down = true
    Button.poll(ctrl, ctx)
    Button.poll(ctrl, ctx)
    Button.poll(ctrl, ctx)
    assert_eq("a press with no release fires no click", clicks.count, 0)
end

-- A touch tap has no held phase, so it fires on the press edge.
do
    local ctrl, ctx, pointer, clicks = setup(true)
    pointer.down = true
    Button.poll(ctrl, ctx)
    assert_eq("a touch press fires one click on the down edge", clicks.count, 1)
    Button.poll(ctrl, ctx)
    assert_eq("a held touch fires no second click", clicks.count, 1)
end

-- The mouse-down latch claims the press without firing, and a latch that never shows as held expires.
do
    local ctrl, ctx, pointer, clicks = setup(false)
    assert_true("the latch on a hovered mouse button consumes the click", Button.pollClick(ctrl, ctx) == true)
    assert_eq("the latch alone fires no click", clicks.count, 0)
    assert_true("the latch leaves the button armed", ctrl.armed == true)
    for _ = 1, 5 do
        Button.poll(ctrl, ctx)
    end
    assert_true("an armed latch survives five polls", ctrl.armed == true)
    Button.poll(ctrl, ctx)
    assert_true("an armed latch that never shows as held expires on the sixth poll", ctrl.armed == false)
    assert_eq("an expired latch fires no click", clicks.count, 0)
    pointer.hovered = false
    assert_true("the latch off the button is not consumed", Button.pollClick(ctrl, ctx) == false)
end

-- The fill helpers repaint the Border behind a transparent Button. A fake Border records the colour it
-- was given, and a fake Button reports the pointer state, so no engine is needed.
local okUmg, Umg = pcall(require, "ModMenu.core.umg")
assert_true("core.umg loads under MoonSharp", okUmg)
if okUmg then
    local function newFill()
        local fill = { color = nil }
        function fill:SetBrushColor(color)
            self.color = color
        end
        return fill
    end
    local function newButton()
        local button = { hovered = false, pressed = false, background = nil }
        function button:IsHovered()
            return self.hovered
        end
        function button:IsPressed()
            return self.pressed
        end
        function button:SetBackgroundColor(color)
            self.background = color
        end
        return button
    end
    local normal = { R = 0.4, G = 0.4, B = 0.4, A = 1 }
    local hover = { R = 0.6, G = 0.6, B = 0.6, A = 1 }
    local pressed = { R = 0.2, G = 0.2, B = 0.2, A = 1 }

    local ctrl = { widget = newButton(), fill = newFill() }
    Umg.SetFillColors(ctrl, normal, hover, pressed)
    assert_eq("SetFillColors paints the resting colour on the fill", ctrl.fill.color, normal)
    assert_eq("SetFillColors makes the button transparent", ctrl.widget.background.A, 0)

    ctrl.widget.hovered = true
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer paints the hover colour", ctrl.fill.color, hover)
    ctrl.widget.pressed = true
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer paints the pressed colour", ctrl.fill.color, pressed)
    ctrl.widget.hovered = false
    ctrl.widget.pressed = false
    Umg.TrackPointer(ctrl)
    assert_eq("TrackPointer returns to the resting colour", ctrl.fill.color, normal)

    local bare = { widget = newButton() }
    bare.widget.hovered = true
    Umg.TrackPointer(bare)
    assert_eq("TrackPointer leaves a control with no fill alone", bare.lastState, nil)

    local derived = { widget = newButton(), fill = newFill() }
    Umg.SetFill(derived, normal)
    derived.widget.hovered = true
    Umg.TrackPointer(derived)
    assert_true("SetFill derives a lighter hover colour", derived.fill.color.R > normal.R)
end