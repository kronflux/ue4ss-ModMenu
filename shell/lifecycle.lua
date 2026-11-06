--[[
  ModMenu.shell.lifecycle — open / close / toggle, poll loop, ClientRestart.
]]

local UEHelpers = require("UEHelpers.UEHelpers")
local Util = require("ModMenu.core.util")
local Input = require("ModMenu.core.input")
local InputMode = require("ModMenu.core.inputmode")
local Instance = require("ModMenu.core.instance")
local Cursor = require("ModMenu.core.cursor")
local Widgets = require("ModMenu.widgets.init")
local Session = require("ModMenu.shell.session")
local Close = require("ModMenu.shell.close")
local Collapse = require("ModMenu.shell.collapse")
local Tabs = require("ModMenu.shell.tabs")
local Build = require("ModMenu.shell.build")
local Confirm = require("ModMenu.shell.confirm")
local Theme = require("ModMenu.core.theme")
local Tooltip = require("ModMenu.core.tooltip")
local Persist = require("ModMenu.core.persist")
local Dock = require("ModMenu.shell.dock")
local Registry = require("ModMenu.shell.registry")

local Log = Util.Log
local Debug = Util.Debug
local IsValid = Util.IsValid
local SafeCall = Util.SafeCall
local Dropdown = Widgets.get("dropdown")

local M = {}

function M.StopPoll(S)
    if S.pollHandle then
        pcall(function()
            CancelDelayedAction(S.pollHandle)
        end)
        S.pollHandle = nil
    end
    -- Keep S.pollFn pinned. CancelDelayedAction can still run this tick;
    -- dropping the Lua function here is what produces "Ref was not function".
end

local function PollControls(S)
    -- The tooltip is polled before the confirm check, so an open confirm dialog hides it.
    -- os.clock is the clock the shell already uses for debounce, and on Windows it counts wall time.
    Tooltip.Poll(S, os.clock() * 1000)
    -- Autosave writes only once its debounce has ended, so on most ticks this is one comparison.
    Persist.Flush()

    if Confirm.Poll(S) then
        return
    end

    local ctx = S.makeWidgetCtx()

    Input.BeginPoll(S.liveControls)

    -- Continuous polls (search filter, checkbox state, UButton IsPressed).
    -- pollClick is the LMB-latch fallback. Handlers must SuppressPressEdge so
    -- a latch click is not also treated as an IsPressed rising edge next tick.
    for _, ctrl in ipairs(S.liveControls) do
        if ctrl.stateDisabled then
            -- A disabled item takes no input and shows no hover.
        elseif ctrl.kind == "close" then
            Close.Poll(S, ctrl)
        elseif ctrl.kind == "collapse" then
            Collapse.Poll(S, ctrl)
        elseif ctrl.kind == "tab" then
            Tabs.Poll(S, ctrl)
        else
            local widget = Widgets.get(ctrl.kind)
            if widget and widget.poll then
                widget.poll(ctrl, ctx)
            end
        end
    end

    if Input.ConsumeMouseClick() then
        -- List order. Dropdown.pollClick does option rows then header.
        local consumed = false
        for _, ctrl in ipairs(S.liveControls) do
            if ctrl.stateDisabled then
                -- A disabled item does not claim the click.
            elseif ctrl.kind == "close" then
                if Close.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            elseif ctrl.kind == "collapse" then
                if Collapse.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            elseif ctrl.kind == "tab" then
                if Tabs.PollClick(S, ctrl) then
                    consumed = true
                    break
                end
            else
                local widget = Widgets.get(ctrl.kind)
                if widget and widget.pollClick and widget.pollClick(ctrl, ctx) then
                    consumed = true
                    break
                end
            end
        end
        if not consumed then
            if not Input.RetryUnclaimedClick() then
                Input.DebugClick("latch-miss", nil, nil)
            end
        end
    end

    -- Collapse show/hide after ipairs so a press-edge + latch cannot both apply.
    Collapse.Flush(S)
    -- Tab rebuild is also deferred — never BuildContent under a still-down click.
    Tabs.Flush(S)
    if S.pendingClose then
        S.pendingClose = false
        M.Close(S)
    end
end

function M.StartPoll(S)
    M.StopPoll(S)
    if S.pollFn == nil then
        S.pollFn = Util.PinFn(function()
            if not S.menuOpen then
                return
            end
            -- Reclaim when the game steals cursor / click routing (toast, etc.).
            -- Look-ignore is opt-in (Init ignoreLook) — do not re-lock the camera by default.
            local pc = UEHelpers.GetPlayerController()
            if InputMode.CursorStolen(pc) then
                InputMode.Reclaim()
            else
                -- Overlay / Wuchang: keep look locked without resetting Slate focus.
                InputMode.RefreshLookIgnore(pc)
            end
            PollControls(S)
        end)
    end
    S.pollHandle = LoopInGameThreadWithDelay(Session.POLL_MS, S.pollFn)
end

--- Host gate for opening (key toggle + ModMenu.Open). Close is never gated.
---@return boolean allowed
---@return string|nil reason
function M.EvaluateCanOpen(S)
    local fn = S.config.canOpen
    if type(fn) ~= "function" then
        return true
    end
    local ok, a, b = pcall(fn)
    if not ok then
        return false, tostring(a)
    end
    if a == false then
        return false, (type(b) == "string" and b ~= "") and b or "canOpen returned false"
    end
    return true
end

---@param opts { skipCanOpen?: boolean }|nil
function M.Open(S, opts)
    opts = opts or {}
    if not opts.skipCanOpen then
        local allowed, reason = M.EvaluateCanOpen(S)
        if not allowed then
            Log("OPEN blocked: " .. tostring(reason))
            return
        end
    end
    -- A host that initializes ConfigManager after ModMenu.Init and Register still gets its
    -- snapshot applied before the first build.
    M.LoadPersist(S)
    if not Build.Ensure(S) then
        return
    end
    -- Keep the UMG tree across open/close. Create already builds content;
    -- rebuilding here respawns every searchable row (Give, keybinds, …).
    -- contentDirty: Register / SetOptions while closed after the first open.
    if S.contentDirty or S.liveControls == nil or #S.liveControls == 0 then
        Build.BuildContent(S)
    end
    S.menuRoot:SetVisibility(Session.VIS_VISIBLE)
    S.menuOpen = true
    Instance.NoteOpened()
    InputMode.SetActive(true)
    M.StartPoll(S)
    if Cursor.IsEnabled(S) then
        if S.cursorShowFn == nil then
            S.cursorShowFn = Util.PinFn(function()
                S.cursorShowHandle = nil
                if S.menuOpen then
                    Cursor.Show(S)
                    Cursor.StartPoll(S)
                end
            end)
        end
        if S.cursorShowHandle ~= nil then
            pcall(function()
                CancelDelayedAction(S.cursorShowHandle)
            end)
            S.cursorShowHandle = nil
        end
        -- Brief delay so the shell is in the viewport before the overlay attaches.
        S.cursorShowHandle = ExecuteInGameThreadWithDelay(50, S.cursorShowFn)
    end
    Debug(string.format("OPEN tag=%s", tostring(Instance.GetTag())))
    for _, fn in ipairs(S.onOpenCallbacks) do
        SafeCall(fn)
    end
end

function M.Close(S)
    Confirm.Hide(S, "close")
    -- Close keeps the tree and the live controls for the next Open, so the tooltip hides but keeps its targets.
    Tooltip.Hide(S)
    M.StopPoll(S)
    if S.cursorShowHandle ~= nil then
        pcall(function()
            CancelDelayedAction(S.cursorShowHandle)
        end)
        S.cursorShowHandle = nil
    end
    Cursor.Hide(S)
    Input.ClearClickState()
    Dropdown.collapseAll(S.liveControls, nil)
    -- Poll stops while the menu is closed, so a keybind capture ends here rather than taking the first key after the next Open.
    Widgets.get("keybind")._stopCapture(S.makeWidgetCtx())
    if IsValid(S.menuRoot) then
        S.menuRoot:SetVisibility(Session.VIS_COLLAPSED)
    end
    S.menuOpen = false
    -- The poll tick has stopped, so a write still in its debounce moves to the timer.
    if Persist.Pending() then
        M.ArmPersistTimer(S)
    end
    local remaining = Instance.NoteClosed()
    InputMode.SetActive(false, remaining)
    Debug(string.format("CLOSED tag=%s openRemaining=%s", tostring(Instance.GetTag()), tostring(remaining)))
end

function M.Toggle(S)
    -- Close is never gated. Open (and recover-to-open) respects canOpen.
    if S.menuOpen and IsValid(S.menuRoot) and Session.IsVisible(S) then
        M.Close(S)
    else
        M.Open(S)
    end
end

-- Write a value as text with table keys sorted, so two equal configs always give the same key.
local function Serialize(v, out)
    local t = type(v)
    if t == "table" then
        local keys = {}
        for k in pairs(v) do
            keys[#keys + 1] = k
        end
        table.sort(keys, function(a, b)
            return tostring(a) < tostring(b)
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = tostring(k)
            out[#out + 1] = "="
            Serialize(v[k], out)
            out[#out + 1] = ","
        end
        out[#out + 1] = "}"
    elseif t == "string" then
        out[#out + 1] = string.format("%q", v)
    else
        out[#out + 1] = tostring(v)
    end
end

--- Return a string that changes when the theme, the theme definition, the style overrides, the colours or the fonts change.
--- Other options leave it equal, so an Init that changes only a title or a key keeps today's in-place update.
---@param config table
---@return string
function M.StyleKey(config)
    local out = {}
    Serialize({
        theme = config.theme,
        themeDef = config.themeDef,
        style = config.style,
        colors = config.colors,
        fonts = config.fonts,
    }, out)
    return table.concat(out)
end

--- Tear the shell down and build it again from the current config, reopening it when it was open.
--- Styles are written into widgets before they are first shown (field note 28), so a new look needs new widgets rather than a repaint.
--- This follows the ClientRestart path: Destroy releases the input mode this shell held, and Open takes it again.
local function RebuildShell(S)
    local wasOpen = S.menuOpen == true
    if wasOpen then
        -- A keybind capture belongs to the widgets being destroyed, so it ends here as it does on Close.
        Widgets.get("keybind")._stopCapture(S.makeWidgetCtx())
    end
    if S.cursorShowHandle ~= nil then
        pcall(function()
            CancelDelayedAction(S.cursorShowHandle)
        end)
        S.cursorShowHandle = nil
    end
    Build.Destroy(S, S.stopPoll or function()
        M.StopPoll(S)
    end)
    -- The cursor records its new config while the menu counts as closed, so it does not build an overlay this
    -- rebuild would throw away; Open shows the overlay again from that record.
    Cursor.OnConfigChanged(S)
    Debug("style changed: shell rebuilt")
    if wasOpen then
        -- The menu was already open, so it is restored without asking the host gate again.
        M.Open(S, { skipCanOpen = true })
        -- A click still latched from before the rebuild must not land on the new widgets, as after a content rebuild.
        Input.ClearClickState()
    end
end

-- The wait before a deferred rebuild, about one frame. It is never 0, because a zero delay has
-- left a game stuck before (field notes), and any positive delay runs after the current poll.
local REBUILD_DELAY_MS = 16

--- True when an Init's look needs the shell torn down and built again: a shell exists and its
--- style key differs from the key it was built with. The first Init has no built key, and an
--- Init that leaves the look alone keeps the in-place update.
---@param builtKey string|nil the key the current shell was built with
---@param key string the key of the current config
---@param hasShell boolean
---@return boolean
function M.NeedsRebuild(builtKey, key, hasShell)
    return builtKey ~= nil and builtKey ~= key and hasShell == true
end

-- Run the rebuild a changed look scheduled. The key is read now, so several Inits in one tick
-- give one rebuild from the latest config, and an Init that put the look back gives none.
local function RunPendingRebuild(S)
    S.rebuildPending = false
    local key = M.StyleKey(S.config)
    if key == S.styleKey then
        return
    end
    S.styleKey = key
    Tabs.Ensure(S)
    if not IsValid(S.menuRoot) then
        -- The shell went away meanwhile, as on ClientRestart, so the next build uses this config already.
        Cursor.OnConfigChanged(S)
        return
    end
    RebuildShell(S)
end

-- A host's onClick can call Init while PollControls walks S.liveControls, so destroying the shell
-- then would pull the list from under that loop. The rebuild waits for a later game-thread tick.
local function ScheduleRebuild(S)
    if S.rebuildPending then
        return
    end
    if S.styleRebuildFn == nil then
        -- Pinned for the session, as the poll function is, so a queued call never meets a dropped function.
        -- It has its own field, because S.rebuildFn holds the registry's content rebuild.
        S.styleRebuildFn = Util.PinFn(function()
            RunPendingRebuild(S)
        end)
    end
    S.rebuildPending = true
    local ok, err = pcall(function()
        ExecuteInGameThreadWithDelay(REBUILD_DELAY_MS, S.styleRebuildFn)
    end)
    if not ok then
        -- Without the delayed call the new look would never show, so the rebuild runs now as it used to.
        Log("style change: could not defer the rebuild (" .. tostring(err) .. "); rebuilding now")
        RunPendingRebuild(S)
    end
end

--- Re-apply panel fill/outline after Init. Rebuild content if the shell exists.
--- When the look changed, the whole shell is rebuilt instead, on a later tick, because panel shapes and widget
--- styles are fixed at build time.
function M.OnConfigChanged(S)
    -- S.styleKey is the key the current shell was built with: it is stored here when no rebuild is needed, and
    -- by the deferred rebuild when that runs, never when one is only scheduled.
    local key = M.StyleKey(S.config)
    local builtKey = S.styleKey
    if M.NeedsRebuild(builtKey, key, IsValid(S.menuRoot)) then
        Tabs.Ensure(S)
        ScheduleRebuild(S)
        return
    end
    S.styleKey = key
    Tabs.Ensure(S)
    local colors = Theme.Of(S.config)
    if IsValid(S.panelBorder) then
        pcall(function()
            S.panelBorder:SetBrushColor(colors.panelBg)
            -- Build's padding keeps a host's spacing.panelPad, which the theme's padding alone would overwrite.
            S.panelBorder:SetPadding(Build.PanelPadding(S.config))
        end)
    end
    if IsValid(S.panelOutline) then
        pcall(function()
            S.panelOutline:SetBrushColor(colors.panelBorder)
        end)
    end
    -- Cursor overlay is independent of the shell tree (first Init has no root yet).
    Cursor.OnConfigChanged(S)
    if not IsValid(S.menuRoot) then
        return
    end
    if S.menuOpen then
        Build.BuildContent(S)
        Input.ClearClickState()
    else
        S.contentDirty = true
    end
end

--- Write a pending snapshot while the menu is closed, when no poll tick runs.
--- One delayed call is armed at a time. If a later change moved the write later, the call arms
--- itself again. While the menu is open the poll tick writes instead.
function M.ArmPersistTimer(S)
    if S.persistTimerArmed then
        return
    end
    if S.persistTimerFn == nil then
        S.persistTimerFn = Util.PinFn(function()
            S.persistTimerArmed = false
            if S.menuOpen then
                return
            end
            Persist.Flush()
            if Persist.Pending() then
                M.ArmPersistTimer(S)
            end
        end)
    end
    S.persistTimerArmed = true
    ExecuteInGameThreadWithDelay(Persist.DEBOUNCE_MS, S.persistTimerFn)
end

--- Queue an autosave write after a change. Nothing is written before the snapshot was read,
--- because a write then would replace the saved state with the author defaults.
function M.PersistChanged(S)
    if not S.persistOn or not S.persistLoaded then
        return
    end
    Persist.Schedule(S.persistStore, S.persistSnapshotFn, Persist.DEBOUNCE_MS)
    if not S.menuOpen then
        M.ArmPersistTimer(S)
    end
end

--- Read the snapshot from the store once, as soon as the host has initialized the store.
--- Until then it is tried again on each Register and Open.
function M.LoadPersist(S)
    if not S.persistOn or S.persistLoaded then
        return
    end
    local store = S.persistStore
    if store == nil or store.File() == nil then
        return
    end
    local ok, snapshot = pcall(store.Get, Persist.KEY)
    S.persistLoaded = true
    if not ok then
        Log("autosave could not read " .. Persist.KEY .. ": " .. tostring(snapshot))
        return
    end
    Registry.ApplySnapshot(S, snapshot)
    Debug("autosave loaded " .. Persist.KEY .. (type(snapshot) == "table" and "" or " (none saved yet)"))
    if IsValid(S.menuRoot) then
        -- The shell was built before the store was ready, so it is laid out again from the snapshot.
        Dock.ApplyPercentLayout(S.panelSlot, S.config)
        Dock.SyncChrome(S)
        Tabs.Ensure(S)
        S.contentDirty = true
    end
end

--- Turn autosave on with the ConfigManager store, or off. Off is what a host gets without
--- Init({ autosave = true }), so nothing is read or written then.
---@param store table|nil the store, nil to turn autosave off
function M.SetPersist(S, store)
    if store == nil then
        S.persistOn = false
        S.onStateChange = nil
        -- A write queued before autosave was turned off is dropped, so nothing is written once it is off.
        Persist.Cancel()
        return
    end
    S.persistOn = true
    S.persistStore = store
    if S.persistSnapshotFn == nil then
        S.persistSnapshotFn = function()
            return Persist.Snapshot(S)
        end
    end
    S.onStateChange = function()
        M.PersistChanged(S)
    end
    M.LoadPersist(S)
end

--- Take the dock and the tab to keep across a later Init, or nil when no snapshot is loaded.
--- Init runs before this when the snapshot is not loaded yet, so only a later Init gets a kept table.
---@return { dock: string|nil, tab: string|nil }|nil
function M.KeepShell(S)
    if not S.persistOn or not S.persistLoaded or type(S.persistSnapshot) ~= "table" then
        return nil
    end
    return {
        dock = S.config.dock,
        tab = S.activeTab or S.persistSnapshot.tab,
    }
end

--- Put back the dock and the tab that KeepShell took, after a later Init wrote its own config.
--- The tab is restored only when the new config lists it, and nothing is restored when autosave is off.
---@param kept { dock: string|nil, tab: string|nil }|nil
function M.RestoreShell(S, kept)
    if kept == nil or not S.persistOn then
        return
    end
    if kept.dock ~= nil then
        S.config.dock = kept.dock
    end
    if Tabs.Has(S, kept.tab) then
        S.activeTab = kept.tab
    end
end

function M.InstallHooks(S)
    if S.hooksInstalled then
        return
    end
    S.hooksInstalled = true
    S.stopPoll = function()
        M.StopPoll(S)
    end

    S.clientRestartFn = Util.PinFn(function()
        local wasOpen = S.menuOpen
        Build.Destroy(S, S.stopPoll)
        -- The next shell is built from the current config, here or at the next Open, so its key is stored now and a
        -- style rebuild still pending finds nothing to do.
        S.styleKey = M.StyleKey(S.config)
        Debug("ClientRestart — shell reset")
        if wasOpen then
            -- Already-open session: restore without re-checking the host gate.
            M.Open(S, { skipCanOpen = true })
        end
    end)

    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function()
        ExecuteInGameThread(S.clientRestartFn)
    end)
end

return M
