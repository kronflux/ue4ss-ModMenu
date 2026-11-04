-- enabled and visible are common to every item. ItemState holds the rules, and the registry's
-- SetEnabled and SetVisible apply them to the nodes a build recorded, without a rebuild.
-- The registry requires UEHelpers through the shell build module, so an empty stub stands in while it loads.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okState, ItemState = pcall(require, "ModMenu.core.itemstate")
local okRegistry, Registry = pcall(require, "ModMenu.shell.registry")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("core.itemstate loads under MoonSharp", okState)
assert_true("shell.registry loads under MoonSharp", okRegistry)
if not (okState and okRegistry) then
    return
end

local function errorOf(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        return nil
    end
    return tostring(err)
end

local function mentions(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

-- Validate: the same message the builder reports, after the item's prefix.
assert_true("Validate accepts an item with no state fields", pcall(ItemState.Validate, {}, "p"))
assert_true("Validate accepts booleans", pcall(ItemState.Validate, { enabled = false, visible = true }, "p"))
assert_true(
    "Validate rejects a non-boolean enabled",
    mentions(errorOf(ItemState.Validate, { enabled = "no" }, "p"), "p enabled must be a boolean")
)
assert_true(
    "Validate rejects a non-boolean visible",
    mentions(errorOf(ItemState.Validate, { visible = 1 }, "p"), "p visible must be a boolean")
)

-- Effective: a disabled or hidden parent wins over a child that says true.
local en, vis = ItemState.Effective({}, nil, nil)
assert_true("an item with no fields is enabled and visible", en == true and vis == true)
en, vis = ItemState.Effective({ enabled = false }, true, true)
assert_true("enabled = false disables only that item", en == false and vis == true)
en, vis = ItemState.Effective({ enabled = true, visible = true }, false, true)
assert_true("a disabled parent disables a child that says true", en == false and vis == true)
en, vis = ItemState.Effective({ visible = true }, true, false)
assert_true("a hidden parent hides a child that says true", en == true and vis == false)

-- Walk visits an item and the children of rows and folds with their effective state.
local tree = {
    id = "f",
    type = "fold",
    enabled = false,
    items = {
        { id = "a", type = "button" },
        { id = "r", type = "row", visible = false, items = { { id = "b", type = "slider" } } },
    },
}
local seen = {}
ItemState.Walk(tree, true, true, function(item, enabled, visible)
    seen[item.id] = { enabled, visible }
end)
assert_eq("Walk gives the fold its own state", seen.f, { false, true })
assert_eq("Walk gives a child the fold's disabled state", seen.a, { false, true })
assert_eq("Walk gives a row inside a disabled fold both states", seen.r, { false, false })
assert_eq("Walk gives a row child the row's hidden state", seen.b, { false, false })

-- Apply writes the state to every recorded node and marks the item's controls.
local function newNode()
    local node = {}
    function node:SetVisibility(value)
        self.visibility = value
    end
    function node:SetRenderOpacity(value)
        self.opacity = value
    end
    function node:SetIsEnabled(value)
        self.enabled = value
    end
    return node
end

local item = { id = "x", type = "label" }
local nodeA, nodeB = newNode(), newNode()
local ctrl = { item = item }
local S = { itemNodes = { [item] = { nodeA, nodeB } }, liveControls = { ctrl } }
ItemState.Apply(S, item, false, true)
assert_eq("Apply dims a disabled item's nodes", nodeA.opacity, ItemState.DISABLED_OPACITY)
assert_eq("Apply disables a disabled item's nodes", nodeB.enabled, false)
assert_eq("Apply keeps a disabled item visible", nodeA.visibility, 0)
assert_eq("Apply marks the item's control disabled", ctrl.stateDisabled, true)
ItemState.Apply(S, item, true, false)
assert_eq("Apply restores full opacity", nodeA.opacity, 1)
assert_eq("Apply collapses a hidden item's nodes", nodeA.visibility, 1)
assert_eq("Apply marks the item's control enabled again", ctrl.stateDisabled, false)

-- SetEnabled and SetVisible change the state in place. No rebuild is queued, the stored value stays,
-- and an unknown item returns false.
local rebuilds = 0
ExecuteInGameThread = function()
    rebuilds = rebuilds + 1
end

local button = { id = "go", type = "button", label = "Go" }
local slider = { id = "speed", type = "slider", label = "Speed", min = 0, max = 10 }
local fold = { id = "more", type = "fold", label = "More", items = { slider } }
local buttonNode, foldNode, sliderNode = newNode(), newNode(), newNode()
local buttonWidget = newNode()
local registryState = {
    values = { ["s.speed"] = 7 },
    liveControls = { { kind = "button", item = button, widget = buttonWidget } },
    sections = { { id = "s", items = { button, fold } } },
    sectionIndexById = { s = 1 },
    itemNodes = { [button] = { buttonNode }, [fold] = { foldNode }, [slider] = { sliderNode } },
    menuOpen = true,
    makeWidgetCtx = function()
        return {}
    end,
}

assert_true("SetEnabled on a known item returns true", Registry.SetEnabled(registryState, "s", "go", false) == true)
assert_eq("SetEnabled stores the flag on the item", button.enabled, false)
assert_eq("SetEnabled dims the item's nodes", buttonNode.opacity, ItemState.DISABLED_OPACITY)
assert_eq("SetEnabled queues no rebuild", rebuilds, 0)
assert_true("SetEnabled on an unknown item returns false", Registry.SetEnabled(registryState, "s", "nope", false) == false)
assert_true("SetEnabled on an unknown section returns false", Registry.SetEnabled(registryState, "zz", "go", false) == false)
assert_true("SetEnabled(true) re-enables the item", Registry.SetEnabled(registryState, "s", "go", true) == true)
assert_eq("SetEnabled(true) restores full opacity", buttonNode.opacity, 1)

assert_true("SetVisible on a fold returns true", Registry.SetVisible(registryState, "s", "more", false) == true)
assert_eq("SetVisible collapses the fold's own nodes", foldNode.visibility, 1)
assert_eq("SetVisible collapses a child of the hidden fold", sliderNode.visibility, 1)
assert_eq("SetVisible leaves the stored value alone", registryState.values["s.speed"], 7)
assert_eq("SetVisible queues no rebuild", rebuilds, 0)
Registry.SetVisible(registryState, "s", "more", true)
assert_eq("SetVisible(true) shows the fold again", foldNode.visibility, 0)
assert_eq("SetVisible(true) shows the child again", sliderNode.visibility, 0)

assert_true(
    "SetButtonEnabled stays and reaches the same state",
    Registry.SetButtonEnabled(registryState, "s", "go", false) == true and button.enabled == false
)

-- A nil item id names no item, so it must not match the first item that has no id.
local separator = { type = "separator" }
local nilIdState = {
    values = {},
    liveControls = {},
    sections = { { id = "s", items = { separator, { id = "go", type = "button", label = "Go" } } } },
    sectionIndexById = { s = 1 },
    itemNodes = { [separator] = { newNode() } },
    menuOpen = true,
    makeWidgetCtx = function()
        return {}
    end,
}
assert_true("SetVisible with a nil item id returns false", Registry.SetVisible(nilIdState, "s", nil, false) == false)
assert_eq("SetVisible with a nil item id leaves an item without an id alone", separator.visible, nil)
assert_true("SetEnabled with a nil item id returns false", Registry.SetEnabled(nilIdState, "s", nil, false) == false)

-- Apply records the hidden state, so a label whose text changes while it is hidden stays collapsed.
local Label = require("ModMenu.widgets.label")
local labelCtx = {
    umg = {
        SetLabelText = function() end,
    },
}
local labelItem = { id = "note", type = "label", label = "Shown" }
local labelWidget, labelPad = newNode(), newNode()
local labelCtrl = { kind = "label", item = labelItem, widget = labelWidget, pad = labelPad }
local labelState = {
    itemNodes = { [labelItem] = { labelWidget, labelPad } },
    liveControls = { labelCtrl },
    makeWidgetCtx = function()
        return labelCtx
    end,
}
ItemState.Apply(labelState, labelItem, true, false)
assert_eq("Apply marks a hidden item's control hidden", labelCtrl.stateHidden, true)
Label.apply(labelCtrl, "New text", labelCtx)
assert_eq("a label given new text while hidden stays collapsed", labelWidget.visibility, 1)
assert_eq("the hidden label's pad stays collapsed", labelPad.visibility, 1)
ItemState.Apply(labelState, labelItem, true, true)
assert_eq("Apply marks a shown item's control not hidden", labelCtrl.stateHidden, false)
assert_eq("showing the label again shows its text", labelWidget.visibility, 0)

-- Disabling a control in the middle of a press drops the press, so enabling it again cannot fire a stale click.
local pressItem = { id = "p", type = "button", label = "P" }
local pressCtrl = { item = pressItem, holding = true, armed = true, armTicks = 2 }
ItemState.Apply({ itemNodes = {}, liveControls = { pressCtrl } }, pressItem, false, true)
assert_eq("disabling a held control clears holding", pressCtrl.holding, false)
assert_eq("disabling an armed control clears armed", pressCtrl.armed, false)
