--[[
  ModMenu.shell.session — mutable per-Lua-state shell fields shared by dock/build/lifecycle.
]]

local Util = require("ModMenu.core.util")

local M = {}

M.VIS_VISIBLE = 0
M.VIS_COLLAPSED = 1
M.POLL_MS = 16

---@param opts { config: table, sections: table, values: table, onOpenCallbacks: table, onDockCallbacks?: table }
function M.New(opts)
    return {
        config = opts.config,
        sections = opts.sections,
        sectionIndexById = {},
        values = opts.values,
        onOpenCallbacks = opts.onOpenCallbacks,
        onDockCallbacks = opts.onDockCallbacks or {},
        menuRoot = nil,
        contentBox = nil,
        menuScroll = nil, ---@type any panel ScrollBox (reset to top after dock change)
        panelSlot = nil,
        panelBorder = nil, ---@type any fill Border
        panelOutline = nil, ---@type any 1px outline Border
        menuOpen = false,
        contentGen = 0,
        pollHandle = nil,
        pollFn = nil, ---@type function|nil strong ref for LoopInGameThreadWithDelay
        hooksInstalled = false,
        liveControls = {},
        -- The widgets each item's build added to the panel, keyed by the item table; see core/itemstate.lua.
        itemNodes = {},
        contentDirty = false, --- rebuild on next Open after Register/SetOptions while closed
        collapsedById = {}, ---@type table<string, boolean>
        foldCollapsedByKey = {}, ---@type table<string, boolean> "sectionId.foldId"
        activeTab = nil, ---@type string|nil session-only; first Init tab when unset
        pendingTabId = nil, ---@type string|nil
        tabApplyQueue = {}, ---@type string[]
        tabApplyFn = nil, ---@type function|nil
        tabApplyScheduled = false,
        pendingCollapseId = nil, ---@type string|nil
        pendingCollapseSource = nil, ---@type string|nil
        collapseApplyQueue = {}, ---@type { id: string, source: string|nil }[]
        collapseApplyFn = nil, ---@type function|nil
        collapseApplyScheduled = false,
        menuCanvas = nil, ---@type any CanvasPanel (panel + confirm overlay)
        confirm = nil, ---@type table|nil active confirm spec
        confirmRoot = nil,
        confirmSlot = nil,
        confirmControls = nil,
        confirmGen = 0,
        makeWidgetCtx = nil, ---@type fun(): table
        -- Opt-in cursorMode = "modmenu" overlay (core/cursor.lua).
        cursorRoot = nil,
        cursorSlot = nil,
        cursorPollHandle = nil,
        cursorPollFn = nil, ---@type function|nil strong ref for LoopInGameThreadWithDelay
        cursorShowFn = nil, ---@type function|nil
        cursorShowHandle = nil,
        clientRestartFn = nil, ---@type function|nil
        rebuildFn = nil, ---@type function|nil the registry's content rebuild
        styleRebuildFn = nil, ---@type function|nil the deferred shell rebuild after a look change (shell/lifecycle.lua)
        rebuildPending = false, -- true while that shell rebuild is scheduled and has not run
        cursorHiddenWidgets = nil, ---@type { widget: any, vis: number|nil }[]|nil
        cursorScale = nil,
        cursorHotspotX = nil,
        cursorHotspotY = nil,
        cursorConfigSig = nil, ---@type string|nil last applied cursorMode|scale|hideClasses
        -- Autosave under __modmenu (core/persist.lua), on only when Init sets autosave = true.
        persistOn = false,
        persistLoaded = false, --- true once the snapshot was read, and only then are changes written
        persistStore = nil, ---@type table|nil the ConfigManager store
        persistSnapshot = nil, ---@type table|nil the snapshot read at load, kept for sections registered later
        persistApplied = {}, ---@type table<string, boolean> sections that already got their snapshot part
        persistSnapshotFn = nil, ---@type function|nil
        persistTimerFn = nil, ---@type function|nil strong ref for ExecuteInGameThreadWithDelay
        persistTimerArmed = false,
        onStateChange = nil, ---@type function|nil set while autosave is on
    }
end

--- Tell autosave that the dock, the tab, a collapse state or a value changed.
--- It does nothing unless Init turned autosave on.
function M.NoteChange(S)
    if type(S.onStateChange) == "function" then
        S.onStateChange()
    end
end

function M.ClearLive(S)
    local list = S.liveControls
    for i = #list, 1, -1 do
        list[i] = nil
    end
    -- The nodes belong to the tree that was just dropped, so they go with the controls.
    for item in pairs(S.itemNodes) do
        S.itemNodes[item] = nil
    end
end

function M.EnsureVisible(S)
    if S.menuOpen and Util.IsValid(S.menuRoot) then
        pcall(function()
            S.menuRoot:SetVisibility(M.VIS_VISIBLE)
        end)
    end
end

function M.IsVisible(S)
    if not Util.IsValid(S.menuRoot) then
        return false
    end
    local ok, vis = pcall(function()
        return S.menuRoot:GetVisibility()
    end)
    return ok and vis == M.VIS_VISIBLE
end

return M
