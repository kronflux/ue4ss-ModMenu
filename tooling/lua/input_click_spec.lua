-- Input.ReleaseClick and Input.ArmClick are the click rule every button-like control shares. They are
-- driven here with a fake widget whose pressed and hovered flags the spec sets, because the real
-- widgets need the engine.
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

local function newWidget()
    local widget = { pressed = false, hovered = true }
    function widget:IsPressed()
        return self.pressed
    end
    function widget:HasMouseCapture()
        return self.pressed
    end
    function widget:IsHovered()
        return self.hovered
    end
    return widget
end

Input.SetPointerMode("mouse")

-- A press then a release over the widget fires once, on the release tick.
do
    local state, widget = {}, newWidget()
    widget.pressed = true
    assert_eq("a held press does not fire", Input.ReleaseClick(state, widget), false)
    assert_eq("a held press stays held", state.holding, true)
    widget.pressed = false
    assert_eq("the release over the widget fires", Input.ReleaseClick(state, widget), true)
    assert_eq("the next idle tick does not fire again", Input.ReleaseClick(state, widget), false)
end

-- A release after the pointer left the widget cancels.
do
    local state, widget = {}, newWidget()
    widget.pressed = true
    Input.ReleaseClick(state, widget)
    widget.hovered = false
    widget.pressed = false
    assert_eq("a release off the widget does not fire", Input.ReleaseClick(state, widget), false)
end

-- The latch arms a hovered mouse press without firing, and does not claim a press off the widget.
do
    local state, widget = {}, newWidget()
    local consumed, now = Input.ArmClick(state, widget)
    assert_eq("the latch on a hovered widget is consumed", consumed, true)
    assert_eq("a mouse latch does not fire now", now, false)
    assert_eq("the latch arms the control", state.armed, true)
    widget.hovered = false
    local missed = Input.ArmClick({}, widget)
    assert_eq("the latch off the widget is not consumed", missed, false)
end

-- An armed press that never shows as held expires after five idle polls.
do
    local state, widget = {}, newWidget()
    Input.ArmClick(state, widget)
    for _ = 1, 5 do
        Input.ReleaseClick(state, widget)
    end
    assert_eq("an armed press survives five idle polls", state.armed, true)
    Input.ReleaseClick(state, widget)
    assert_eq("an armed press expires on the sixth idle poll", state.armed, false)
end

-- A touch tap fires on the press edge, and the latch fires it at once.
do
    Input.SetPointerMode("touch")
    local state, widget = {}, newWidget()
    widget.pressed = true
    assert_eq("a touch press fires on the down edge", Input.ReleaseClick(state, widget), true)
    assert_eq("a held touch does not fire again", Input.ReleaseClick(state, widget), false)
    local consumed, now = Input.ArmClick({}, newWidget())
    assert_eq("a touch latch is consumed", consumed, true)
    assert_eq("a touch latch fires now", now, true)
    Input.SetPointerMode("mouse")
end

assert_eq("ReleaseClick with no state fires nothing", Input.ReleaseClick(nil, newWidget()), false)
