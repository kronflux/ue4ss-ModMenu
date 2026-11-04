--[[
  ModMenu.core.itemstate: the enabled and visible flags every item accepts.

  A disabled item draws dim and ignores input. A hidden item takes no space but keeps its value, so
  autosave still stores it. A row or fold passes both flags to its children, so a disabled or hidden
  parent wins over a child that says true.

  A build records the widgets each item added to the panel in S.itemNodes, keyed by the item table
  (core/umg.lua RecordNode), and Apply writes the state to those nodes without a rebuild.
]]

local ItemState = {}

-- ESlateVisibility::Visible and ::Collapsed.
local VIS_VISIBLE = 0
local VIS_COLLAPSED = 1

--- A disabled item is drawn at this opacity.
ItemState.DISABLED_OPACITY = 0.45

--- Raise when enabled or visible is set and is not a boolean. The messages match the builder's.
---@param item table
---@param prefix string
function ItemState.Validate(item, prefix)
    if item.enabled ~= nil and type(item.enabled) ~= "boolean" then
        error(prefix .. " enabled must be a boolean")
    end
    if item.visible ~= nil and type(item.visible) ~= "boolean" then
        error(prefix .. " visible must be a boolean")
    end
end

--- The state an item has once its parent's state is counted. A parent state of nil means no parent.
---@param item table
---@param parentEnabled boolean|nil
---@param parentVisible boolean|nil
---@return boolean enabled
---@return boolean visible
function ItemState.Effective(item, parentEnabled, parentVisible)
    local enabled = parentEnabled ~= false and item.enabled ~= false
    local visible = parentVisible ~= false and item.visible ~= false
    return enabled, visible
end

--- Call fn(item, enabled, visible) for an item and for the children of rows and folds at any depth,
--- each with its effective state.
---@param item table
---@param parentEnabled boolean|nil
---@param parentVisible boolean|nil
---@param fn fun(item: table, enabled: boolean, visible: boolean)
function ItemState.Walk(item, parentEnabled, parentVisible, fn)
    local enabled, visible = ItemState.Effective(item, parentEnabled, parentVisible)
    fn(item, enabled, visible)
    if (item.type == "row" or item.type == "fold") and type(item.items) == "table" then
        for _, child in ipairs(item.items) do
            if type(child) == "table" then
                ItemState.Walk(child, enabled, visible, fn)
            end
        end
    end
end

--- Write one item's effective state to the nodes its build recorded and to its live controls.
--- It makes no rebuild. A control marked stateDisabled is skipped by the shell poll.
---@param S table the shell state; itemNodes and liveControls are read
---@param item table
---@param enabled boolean
---@param visible boolean
function ItemState.Apply(S, item, enabled, visible)
    local nodes = S.itemNodes and S.itemNodes[item] or {}
    for _, node in ipairs(nodes) do
        pcall(function()
            node:SetVisibility(visible and VIS_VISIBLE or VIS_COLLAPSED)
        end)
        pcall(function()
            node:SetRenderOpacity(enabled and 1 or ItemState.DISABLED_OPACITY)
        end)
        pcall(function()
            node:SetIsEnabled(enabled)
        end)
    end
    local ctx = nil
    for _, ctrl in ipairs(S.liveControls or {}) do
        if ctrl.item == item then
            ctrl.stateDisabled = not enabled
            -- A widget that rewrites its own visibility, such as a label given new text, reads stateHidden.
            ctrl.stateHidden = not visible
            -- The poll skips a disabled control, so a press in progress would wait and fire once it is enabled.
            if not enabled then
                require("ModMenu.core.input").ClearPress(ctrl)
            end
            -- A widget that paints from the state, such as the button's disabled chrome, or that has its
            -- own visibility to restore, such as a collapsed fold body, says so with onItemState.
            pcall(function()
                local widget = require("ModMenu.widgets.init").get(ctrl.kind)
                if widget ~= nil and widget.onItemState ~= nil then
                    ctx = ctx or (S.makeWidgetCtx and S.makeWidgetCtx()) or {}
                    widget.onItemState(ctrl, enabled, visible, ctx)
                end
            end)
        end
    end
end

--- Apply the effective state to every item in a list and to the children of rows and folds.
--- With onlyChanged, an item that is enabled and visible is left alone, so a build does not
--- rewrite the visibility of nodes that are collapsed on purpose, such as a folded body.
---@param S table
---@param items table[]
---@param onlyChanged boolean|nil
function ItemState.ApplyItems(S, items, onlyChanged)
    for _, item in ipairs(items or {}) do
        if type(item) == "table" then
            ItemState.Walk(item, true, true, function(node, enabled, visible)
                if onlyChanged and enabled and visible then
                    return
                end
                ItemState.Apply(S, node, enabled, visible)
            end)
        end
    end
end

return ItemState
