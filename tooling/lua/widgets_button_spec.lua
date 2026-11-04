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

--- A pointer the spec drives by setting fields; the widget and context read it on each poll.
local function newPointer(touch)
    return { down = false, hovered = true, touch = touch == true, wasDown = false }
end

local function newContext(pointer, clicks)
    return {
        Input = {
            IsTouch = function()
                return pointer.touch
            end,
            WidgetIsDown = function()
                return pointer.down
            end,
            WidgetHovered = function()
                return pointer.hovered
            end,
            WidgetPressedEdge = function(state)
                local wentDown = pointer.down and not state.wasPressed
                state.wasPressed = pointer.down
                return wentDown
            end,
            DebugClick = function() end,
            SuppressPressEdge = function() end,
            IgnoreClicks = function() end,
        },
        SafeCall = function(fn)
            fn()
        end,
        ReclaimMenuInput = function() end,
        clicks = clicks,
    }
end

local function newControl(clicks)
    return {
        kind = "button",
        widget = {},
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
    return newControl(clicks), newContext(pointer, clicks), pointer, clicks
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
