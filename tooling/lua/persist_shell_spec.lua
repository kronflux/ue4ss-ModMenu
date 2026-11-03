-- Specs for the shell side of autosave: the registry's re-seed, the teardown flush, turning autosave off,
-- and the dock and tab kept across a later Init.
-- The shell modules require UEHelpers from the UE4SS install, so an empty stub stands in while they load.
local Persist = require("ModMenu.core.persist")
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Registry = require("ModMenu.shell.registry")
local Lifecycle = require("ModMenu.shell.lifecycle")
local Build = require("ModMenu.shell.build")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end

-- The spec host has no os.clock, so a fixed fake clock stands in while Schedule runs and is restored at the end.
local clockBefore = Persist._clock
Persist._clock = function()
    return 0
end

-- A closed shell with no UMG tree and no live controls, so Register and Set touch only the state tables.
local function NewShell()
    return {
        config = { dock = "right" },
        sections = {},
        sectionIndexById = {},
        values = {},
        liveControls = {},
        collapsedById = {},
        foldCollapsedByKey = {},
        persistApplied = {},
        menuOpen = false,
        makeWidgetCtx = function()
            return {}
        end,
    }
end

local function Section()
    return {
        id = "C",
        items = {
            { type = "checkbox", id = "on", label = "On", default = true },
            { type = "dropdown", id = "pick", label = "Pick", options = { "a", "b" }, default = "a" },
        },
    }
end

-- A value cleared with Set(nil) stays cleared after a restart, whether the snapshot loads before or after Register.
local before = NewShell()
Registry.Register(before, Section())
Registry.Set(before, "C", "on", nil)
Registry.Set(before, "C", "pick", nil)
local saved = Persist.Snapshot(before)

local loadFirst = NewShell()
Registry.ApplySnapshot(loadFirst, saved)
Registry.Register(loadFirst, Section())
assert_eq("a checkbox cleared with Set(nil) stays cleared when the snapshot loads before Register", Registry.Get(loadFirst, "C", "on"), nil)
assert_eq("a dropdown cleared with Set(nil) stays cleared when the snapshot loads before Register", Registry.Get(loadFirst, "C", "pick"), nil)

local registerFirst = NewShell()
Registry.Register(registerFirst, Section())
Registry.ApplySnapshot(registerFirst, saved)
assert_eq("a checkbox cleared with Set(nil) stays cleared when the snapshot loads after Register", Registry.Get(registerFirst, "C", "on"), nil)
assert_eq("a dropdown cleared with Set(nil) stays cleared when the snapshot loads after Register", Registry.Get(registerFirst, "C", "pick"), nil)

local untouched = NewShell()
Registry.ApplySnapshot(untouched, { values = {} })
Registry.Register(untouched, Section())
assert_eq("an item the snapshot does not clear still gets its default", Registry.Get(untouched, "C", "on"), true)

-- Destroy writes a pending snapshot at once, because the poll tick and the timer stop with the shell.
-- The rest of Destroy reaches ModRef state that the spec host does not have, so it runs inside a pcall.
local writes = 0
-- File returns nil, so SetPersist does not try to read a snapshot from this store.
local store = {
    Set = function()
        writes = writes + 1
        return true
    end,
    File = function()
        return nil
    end,
}
Persist.Schedule(store, function()
    return { n = 1 }
end, 300)
pcall(Build.Destroy, NewShell(), nil)
assert_eq("Destroy writes the pending snapshot", writes, 1)
assert_true("Destroy leaves no write pending", not Persist.Pending())
Persist.Flush(true)

-- Turning autosave off inside the debounce drops the pending write.
-- The shell counts as open, so PersistChanged leaves the write to the poll tick and arms no UE4SS timer.
local off = NewShell()
off.menuOpen = true
Lifecycle.SetPersist(off, store)
off.persistLoaded = true
Lifecycle.PersistChanged(off)
assert_true("a change with autosave on queues a write", Persist.Pending())
Lifecycle.SetPersist(off, nil)
assert_true("turning autosave off leaves no write pending", not Persist.Pending())
local writesBefore = writes
Persist.Flush(true)
assert_eq("a forced Flush after autosave is off writes nothing", writes, writesBefore)

-- A later Init keeps the loaded dock and tab. The tab applies once Init lists it.
local later = NewShell()
later.persistOn = true
later.persistLoaded = true
Registry.ApplySnapshot(later, { dock = "left", tab = "Give" })
assert_eq("the snapshot dock applies at load", later.config.dock, "left")
assert_true("Lifecycle.KeepShell is a function", type(Lifecycle.KeepShell) == "function")
assert_true("Lifecycle.RestoreShell is a function", type(Lifecycle.RestoreShell) == "function")
if type(Lifecycle.KeepShell) == "function" and type(Lifecycle.RestoreShell) == "function" then
    local kept = Lifecycle.KeepShell(later)
    -- These two lines are what Init({ dock = "top", tabs = { "Cheats", "Give" } }) does to the config.
    later.config.dock = "top"
    later.config.tabs = { "Cheats", "Give" }
    Lifecycle.RestoreShell(later, kept)
    assert_eq("a later Init dock does not replace the loaded dock", later.config.dock, "left")
    assert_eq("a later Init that adds tabs restores the loaded tab", later.activeTab, "Give")

    -- The player's dock change after load is what a later Init keeps, not the dock read at load.
    later.config.dock = "bottom"
    kept = Lifecycle.KeepShell(later)
    later.config.dock = "top"
    Lifecycle.RestoreShell(later, kept)
    assert_eq("a later Init keeps the dock the player chose after load", later.config.dock, "bottom")

    local none = NewShell()
    local keptNone = Lifecycle.KeepShell(none)
    none.config.dock = "top"
    Lifecycle.RestoreShell(none, keptNone)
    assert_eq("without a loaded snapshot a later Init dock applies", none.config.dock, "top")
end

Persist._clock = clockBefore
