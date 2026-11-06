--[[
  ModMenu.shell.close — title-row Close button and the caption buttons and traffic lights of the
  window frames. Same path as the toggle key.
]]

local Input = require("ModMenu.core.input")
local Paint = require("ModMenu.core.paint")
local Motion = require("ModMenu.core.motion")

local M = {}

--- True when a click on the control closes the menu. A window frame's maximise button and the
--- green traffic light carry action "none" and only show their looks.
---@param ctrl table
---@return boolean
function M.ClosesMenu(ctrl)
    return ctrl.action ~= "none"
end

local function Request(S, ctrl)
    -- The click is consumed either way, so the same press is not read again as a release click.
    Input.SuppressPressEdge(ctrl)
    Input.IgnoreClicks(2)
    -- Every press of a close control pops the menu, including a maximise button that closes nothing.
    Motion.Pop(S)
    if M.ClosesMenu(ctrl) then
        S.pendingClose = true
    end
end

--- Call ctrl.onState once whenever the shown state changed since the last call. A control draws
--- its own pointer looks as shapes, and onState covers the swaps a shape cannot, such as the white
--- cross on a hovered Windows 11 close button or the symbols on all three traffic lights.
---@param ctrl table
function M.NotifyState(ctrl)
    if ctrl.onState == nil or ctrl.lastState == ctrl.notifiedState then
        return
    end
    ctrl.notifiedState = ctrl.lastState
    -- A glyph swap that fails must not stop the poll that closes the menu.
    pcall(ctrl.onState, ctrl.lastState)
end

function M.Poll(S, ctrl)
    -- Paint.TrackPointer swaps the shapes of a rounded Close and calls Umg.TrackPointer for a flat one.
    Paint.TrackPointer(ctrl)
    M.NotifyState(ctrl)
    if Input.ReleaseClick(ctrl, ctrl.widget) then
        Input.DebugClick("release", ctrl, ctrl.widget)
        Request(S, ctrl)
    end
end

---@return boolean
function M.PollClick(S, ctrl)
    local consumed, fireNow = Input.ArmClick(ctrl, ctrl.widget)
    if fireNow then
        Input.DebugClick("latch-hover", ctrl, ctrl.widget)
        Request(S, ctrl)
    end
    return consumed
end

return M
