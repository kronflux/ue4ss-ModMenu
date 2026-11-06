--[[
  ModMenu.shell.close — title-row Close button. Same path as the toggle key.
]]

local Input = require("ModMenu.core.input")
local Paint = require("ModMenu.core.paint")

local M = {}

local function Request(S, ctrl)
    Input.SuppressPressEdge(ctrl)
    Input.IgnoreClicks(2)
    S.pendingClose = true
end

function M.Poll(S, ctrl)
    -- Paint.TrackPointer swaps the shapes of a rounded Close and calls Umg.TrackPointer for a flat one.
    Paint.TrackPointer(ctrl)
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