-- Arrow buttons on the dropdown header, the number field's step buttons and the stepper's buttons.
-- The widgets are built from a fake UMG that records each widget by class and name.
local Style = require("ModMenu.core.style")
local Dropdown = require("ModMenu.widgets.dropdown")
local Number = require("ModMenu.widgets.number")
local Stepper = require("ModMenu.widgets.stepper")
local Umg = require("ModMenu.core.umg")

local created = {}
local function Vivify()
    return setmetatable({}, {
        __index = function(t, k)
            local v = Vivify()
            rawset(t, k, v)
            return v
        end,
    })
end
local fakeMeta = {}
fakeMeta.__index = function(self, key)
    if key == "IsValid" then
        return function()
            return true
        end
    end
    local isMethod = key:match("^AddChild") or key:match("^Set") or key:match("^Is") or key:match("^Get")
    if key:match("^%u") and not isMethod then
        local v = Vivify()
        rawset(self, key, v)
        return v
    end
    return function(w, ...)
        local args = { ... }
        w.calls[#w.calls + 1] = { key, args }
        if key == "SetVisibility" then
            w.visibility = args[1]
        end
        if key:match("^AddChildTo") or key == "SetContent" then
            w.children[#w.children + 1] = args[1]
            return setmetatable({ calls = {}, children = {} }, fakeMeta)
        end
        return nil
    end
end
local realConstruct, realFName, realFindObject = StaticConstructObject, FName, StaticFindObject
StaticFindObject = function(path)
    return { path = path, IsValid = function() return true end }
end
FName = function(n)
    return n
end
StaticConstructObject = function(cls, outer, name)
    local w = setmetatable({ class = cls.path, name = name, calls = {}, children = {} }, fakeMeta)
    created[#created + 1] = w
    return w
end
local function Named(name)
    for _, w in ipairs(created) do
        if w.name == name then
            return w
        end
    end
    return nil
end
local function Reset()
    created = {}
end

local white = { R = 1, G = 1, B = 1, A = 1 }
local grey = { R = 0.5, G = 0.5, B = 0.5, A = 1 }
local black = { R = 0, G = 0, B = 0, A = 1 }
local function Slate(withArrow, stepperArrows)
    local resolved = Style.Resolve("slate")
    if withArrow then
        resolved.field.arrow = { face = { white, grey }, glyph = black, size = 17 }
    end
    if stepperArrows then
        resolved.stepper.arrows = true
    end
    return resolved
end

-- The first bar of a triangle is its tip or its base, so its size gives the direction: a one unit
-- bar first is up (wide bars) or left (tall bars), and a seven unit bar first is down or right.
local function FirstBar(triName)
    local bar = Named(triName .. "_BarSize1")
    local size = {}
    for _, call in ipairs(bar.calls) do
        size[call[1]] = call[2][1]
    end
    return size.SetWidthOverride, size.SetHeightOverride
end

-- Dropdown header.
local options = { { label = "A", value = "a" }, { label = "B", value = "b" } }
Reset()
local _, plainPicker = Dropdown._createPicker(nil, "DD", options, "a", {}, { resolved = Slate(false), fontScale = 1 })
assert_true("dropdown without field.arrow keeps the arrow TextBlock", Named("DD_Arrow") ~= nil)
assert_eq("dropdown without field.arrow has no arrow button", Named("DD_ArrowBtn_Btn"), nil)
assert_true("dropdown without field.arrow keeps arrowLabel", plainPicker.arrowLabel ~= nil)

Reset()
local _, arrowPicker = Dropdown._createPicker(nil, "DD", options, "a", {}, { resolved = Slate(true), fontScale = 1 })
assert_true("dropdown with field.arrow has _ArrowBtn", Named("DD_ArrowBtn_Btn") ~= nil)
assert_eq("dropdown with field.arrow has no _Arrow TextBlock", Named("DD_Arrow"), nil)
assert_eq("dropdown arrow has no label", arrowPicker.arrowLabel, nil)
assert_eq("dropdown arrow is hit-test invisible so the header opens the list", Named("DD_ArrowBtn_Size").visibility, 3)
local ddW, ddH = FirstBar("DD_ArrowBtn_Tri")
assert_eq("dropdown arrow is a down triangle: widest bar first", { ddW, ddH }, { 7, 1 })

-- A header click opens the list with the arrow button in place. The click path reads core.input,
-- so its pointer reads are replaced for the call and put back.
local Input = require("ModMenu.core.input")
local savedInput = {}
local asked = {}
for _, key in ipairs({ "ArmClick", "WidgetHovered", "DebugClick", "SuppressPressEdge", "IgnoreClicks" }) do
    savedInput[key] = Input[key]
end
Input.ArmClick = function(_, widget)
    asked[#asked + 1] = widget
    return widget == arrowPicker.headerBtn, true
end
Input.WidgetHovered = function() return false end
Input.DebugClick = function() end
Input.SuppressPressEdge = function() end
Input.IgnoreClicks = function() end
local ddCtrl = Dropdown.liveControl(arrowPicker, { item = {}, valueKey = "s.d" })
local ddCtx = {
    liveControls = { ddCtrl },
    values = {},
    SafeCall = function() end,
    ReclaimMenuInput = function() end,
    EnsureMenuVisible = function() end,
}
assert_true("a header click is consumed with field.arrow", Dropdown.pollHeaderClick(ddCtrl, ddCtx))
assert_true("a header click opens the list with field.arrow", ddCtrl.expanded)
assert_eq("the header button is what the click path asks", asked[1], arrowPicker.headerBtn)

-- The arrow shows the header's pointer state, though it never sees the pointer itself.
local Paint = require("ModMenu.core.paint")
local savedTrack, savedRelease = Paint.TrackPointer, Input.ReleaseClick
local pointer = "hover"
Paint.TrackPointer = function(ctrl)
    Paint.ShowState(ctrl, pointer)
end
Input.ReleaseClick = function() return false end
Dropdown.poll(ddCtrl, ddCtx)
assert_eq("a hovered header shows the arrow's hover look", arrowPicker.arrowBtn.button.lastState, "hover")
assert_eq("the hover look is a shape shown on the arrow", arrowPicker.arrowBtn.button.shownKey, "hover")
pointer = "pressed"
Dropdown.poll(ddCtrl, ddCtx)
assert_eq("a pressed header shows the arrow's pressed look", arrowPicker.arrowBtn.button.lastState, "pressed")
Paint.TrackPointer, Input.ReleaseClick = savedTrack, savedRelease
for key, fn in pairs(savedInput) do
    Input[key] = fn
end

-- Touch: the dropdown arrow is at least 28.
Reset()
Dropdown._createPicker(nil, "DD", options, "a", {}, { resolved = Slate(true), fontScale = 1, pointerMode = "touch" })
local touchDD = {}
for _, call in ipairs(Named("DD_ArrowBtn_Size").calls) do
    touchDD[call[1]] = call[2][1]
end
assert_eq("touch: the dropdown arrow is 28 wide and tall", { touchDD.SetWidthOverride, touchDD.SetHeightOverride }, { 28, 28 })
Reset()
Dropdown._createPicker(nil, "DD", options, "a", {}, { resolved = Slate(true), fontScale = 1, pointerMode = "mouse" })
assert_eq("desktop: the dropdown arrow stays 17", Named("DD_ArrowBtn_Size").calls[1][2][1], 17)

-- Number field.
local function BuildNumber(resolved, item, pointerMode)
    Reset()
    local values = {}
    local ctx = {
        umg = Umg,
        item = item,
        config = { resolved = resolved, fontItem = 16, fontScale = 1, pointerMode = pointerMode },
        namePrefix = "N",
        layout = "vertical",
        section = { id = "s" },
        values = values,
        liveControls = {},
        contentBox = setmetatable({ calls = {}, children = {} }, fakeMeta),
        ValueKey = function(sectionId, id)
            return sectionId .. "." .. id
        end,
        RecordNode = function() end,
    }
    Number.build(ctx)
    return ctx, ctx.liveControls[1]
end
local stepItem = { id = "n", label = "N", min = 0, max = 10, step = 2, default = 4 }

local _, plainNum = BuildNumber(Slate(false), stepItem)
assert_true("number without field.arrow keeps its plus button", Named("N_plus_Btn") ~= nil and Named("N_minus_Btn") ~= nil)
assert_eq("number without field.arrow has no _StepUp", Named("N_StepUp_Btn"), nil)
assert_eq("number without field.arrow has two step buttons", #plainNum.stepButtons, 2)

local ctx, num = BuildNumber(Slate(true), stepItem)
assert_true("number with field.arrow has _StepUp", Named("N_StepUp_Btn") ~= nil)
assert_true("number with field.arrow has _StepDown", Named("N_StepDown_Btn") ~= nil)
assert_eq("number with field.arrow drops the plus button", Named("N_plus_Btn"), nil)
assert_eq("number with field.arrow has two step buttons", #num.stepButtons, 2)
assert_true("the stack is a VerticalBox", Named("N_StepStack") ~= nil and Named("N_StepStack").class == "/Script/UMG.VerticalBox")
local sizes = {}
for _, call in ipairs(Named("N_StepUp_Size").calls) do
    sizes[call[1]] = call[2][1]
end
assert_eq("an arrow step button is arrow.size wide", sizes.SetWidthOverride, 17)
assert_eq("an arrow step button is arrow.size/2 + 1 tall", sizes.SetHeightOverride, 9)

local clicked = nil
ctx.Input = {
    ArmClick = function(stepCtrl)
        return stepCtrl == clicked, true
    end,
    SuppressPressEdge = function() end,
    IgnoreClicks = function() end,
    ClearPress = function() end,
    ReleaseClick = function() return false end,
}
ctx.SafeCall = function(fn, ...)
    if type(fn) == "function" then
        fn(...)
    end
end
ctx.ReclaimMenuInput = function() end
ctx.values["s.n"] = 4
local fired = nil
stepItem.onChange = function(v)
    fired = v
end
for _, b in ipairs(num.stepButtons) do
    if b.dir == 1 then
        clicked = b
    end
end
assert_true("a click on the up arrow is consumed", Number.pollClick(num, ctx))
assert_eq("a click on _StepUp raises the value by step", ctx.values["s.n"], 6)
assert_eq("a click on _StepUp fires onChange", fired, 6)
for _, b in ipairs(num.stepButtons) do
    if b.dir == -1 then
        clicked = b
    end
end
Number.pollClick(num, ctx)
assert_eq("a click on _StepDown lowers the value by step", ctx.values["s.n"], 4)
stepItem.onChange = nil
local upW, upH = FirstBar("N_StepUp_Tri")
local downW, downH = FirstBar("N_StepDown_Tri")
assert_eq("_StepUp is an up triangle: narrowest bar first", { upW, upH }, { 1, 1 })
assert_eq("_StepDown is a down triangle: widest bar first", { downW, downH }, { 7, 1 })

-- Touch: each stacked button is at least 28 tall and wide; desktop is unchanged (17 by 9, above).
BuildNumber(Slate(true), stepItem, "touch")
for _, key in ipairs({ "N_StepUp_Size", "N_StepDown_Size" }) do
    local touchSize = {}
    for _, call in ipairs(Named(key).calls) do
        touchSize[call[1]] = call[2][1]
    end
    assert_eq("touch: " .. key .. " is 28 wide and tall", { touchSize.SetWidthOverride, touchSize.SetHeightOverride }, { 28, 28 })
end

-- A disabled number shows the disabled look on its arrow buttons, and the enabled one the normal look.
local Input2 = { ClearPress = function() end }
Number.onItemState(num, false, true, { Input = Input2 })
assert_eq("a disabled number disables the up arrow", { num.stepButtons[1].enabled, num.stepButtons[1].lastState }, { false, "disabled" })
assert_eq("a disabled number disables the down arrow", { num.stepButtons[2].enabled, num.stepButtons[2].lastState }, { false, "disabled" })
Number.onItemState(num, true, true, { Input = Input2 })
assert_eq("an enabled number shows the normal look", { num.stepButtons[1].enabled, num.stepButtons[1].lastState }, { true, "normal" })

-- Stepper.
local function BuildStepper(resolved, pointerMode)
    Reset()
    local item = { id = "p", label = "P", min = 0, max = 10, step = 1 }
    local sctx = {
        umg = Umg,
        item = item,
        config = { resolved = resolved, fontItem = 16, fontScale = 1, pointerMode = pointerMode },
        namePrefix = "S",
        layout = "vertical",
        section = { id = "s" },
        values = {},
        liveControls = {},
        contentBox = setmetatable({ calls = {}, children = {} }, fakeMeta),
        ValueKey = function(sectionId, id)
            return sectionId .. "." .. id
        end,
        RecordNode = function() end,
    }
    Stepper.build(sctx)
    return sctx.liveControls[1]
end
local plainStep = BuildStepper(Slate(true, false))
assert_eq("a stepper without arrows has no triangles", Named("S_minus_Tri"), nil)
assert_eq("a stepper without arrows keeps two buttons", #plainStep.buttons, 2)
local arrowStep = BuildStepper(Slate(true, true))
assert_true("a stepper with arrows has a left triangle", Named("S_minus_Tri") ~= nil)
assert_true("a stepper with arrows has a right triangle", Named("S_plus_Tri") ~= nil)
assert_eq("a stepper with arrows has two buttons", #arrowStep.buttons, 2)
local leftW, leftH = FirstBar("S_minus_Tri")
local rightW, rightH = FirstBar("S_plus_Tri")
assert_eq("the minus button is a left triangle: shortest bar first", { leftW, leftH }, { 1, 1 })
assert_eq("the plus button is a right triangle: tallest bar first", { rightW, rightH }, { 1, 7 })
assert_eq("the minus button steps down", arrowStep.buttons[1].dir, -1)
assert_eq("the plus button steps up", arrowStep.buttons[2].dir, 1)
BuildStepper(Slate(true, true), "touch")
for _, key in ipairs({ "S_minus_Size", "S_plus_Size" }) do
    local touchSize = {}
    for _, call in ipairs(Named(key).calls) do
        touchSize[call[1]] = call[2][1]
    end
    assert_eq("touch: " .. key .. " is 28 wide and tall", { touchSize.SetWidthOverride, touchSize.SetHeightOverride }, { 28, 28 })
end
local noField = BuildStepper(Slate(false, true))
assert_eq("arrows without field.arrow falls back to text buttons", Named("S_minus_Tri"), nil)
assert_eq("the fallback still has two buttons", #noField.buttons, 2)

StaticConstructObject, FName, StaticFindObject = realConstruct, realFName, realFindObject
