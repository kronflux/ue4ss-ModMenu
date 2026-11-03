-- Specs for core/persist.lua, the autosave of dock, tab, collapse state and values under __modmenu.
-- The state tables are plain tables shaped like the shell's state, because the shell cannot load here.

local Persist = require("ModMenu.core.persist")
local Store = require("ModMenu.core.store")
local Json = require("ModMenu.store.json")

local tmp = (_REPO .. "/tooling/.tmp-persist-spec.json"):gsub("\\", "/")

local function RemoveTemp()
    pcall(os.remove, tmp)
    pcall(os.remove, tmp .. ".tmp")
    pcall(os.remove, tmp .. ".prev")
    pcall(os.remove, tmp .. ".bad")
end

local function Sections()
    return {
        {
            id = "Sec",
            collapsible = true,
            items = {
                { type = "checkbox", id = "on", label = "On" },
                { type = "button", id = "run", label = "Run" },
                { type = "row", items = {
                    { type = "number", id = "count", label = "Count" },
                } },
                { type = "fold", id = "more", label = "More", items = {
                    { type = "textinput", id = "name", label = "Name" },
                } },
            },
        },
        { id = "Other", items = { { type = "label", id = "hint", label = "Hint" } } },
    }
end

local function NewState(dock, tab)
    return {
        config = { dock = dock or "right", tabs = { "A", "B" } },
        activeTab = tab or "A",
        sections = Sections(),
        collapsedById = {},
        foldCollapsedByKey = {},
        values = {},
    }
end

-- Snapshot keeps only value-bearing items, so a button, a label and a stray value are left out.
local state = NewState("left", "B")
state.values["Sec.on"] = true
state.values["Sec.count"] = 3
state.values["Sec.name"] = "Ann"
state.values["Sec.run"] = "not a value item"
state.values["Gone.old"] = 1
state.collapsedById["Sec"] = true
state.foldCollapsedByKey["Sec.more"] = false

local snap = Persist.Snapshot(state)
assert_eq("Snapshot dock", snap.dock, "left")
assert_eq("Snapshot tab", snap.tab, "B")
assert_eq("Snapshot values keep value-bearing items only", snap.values,
    { ["Sec.on"] = true, ["Sec.count"] = 3, ["Sec.name"] = "Ann" })
assert_eq("Snapshot collapsed holds the section only", snap.collapsed, { Sec = true })
assert_eq("Snapshot folds holds the fold", snap.folds, { ["Sec.more"] = false })

-- A section id and a fold key can be the same string, so sections and folds are saved in separate maps.
local function ClashState()
    return {
        config = { dock = "right" },
        sections = {
            { id = "A", items = { { type = "fold", id = "more", label = "More", items = {} } } },
            { id = "A.more", collapsible = true, items = {} },
        },
        collapsedById = {},
        foldCollapsedByKey = {},
        values = {},
    }
end
local clash = ClashState()
clash.collapsedById["A.more"] = true
clash.foldCollapsedByKey["A.more"] = false
local clashSnap = Persist.Snapshot(clash)
assert_eq("Snapshot keeps a section whose id matches a fold key", clashSnap.collapsed["A.more"], true)
assert_eq("Snapshot keeps the fold whose key matches a section id", clashSnap.folds and clashSnap.folds["A.more"], false)
local clashFresh = ClashState()
Persist.Apply(clashSnap, clashFresh)
assert_eq("Apply restores the section whose id matches a fold key", clashFresh.collapsedById["A.more"], true)
assert_eq("Apply restores the fold whose key matches a section id", clashFresh.foldCollapsedByKey["A.more"], false)

-- A write starts from the kept snapshot, so a section not registered this session keeps its saved state.
local partial = NewState("left", "B")
partial.persistSnapshot = {
    dock = "top",
    collapsed = { Gone = true },
    folds = { ["Gone.f"] = true },
    values = { ["Gone.old"] = 1, ["Sec.on"] = false },
}
partial.values["Sec.on"] = true
local partialSnap = Persist.Snapshot(partial)
assert_eq("Snapshot keeps the saved value of a section not registered this session", partialSnap.values["Gone.old"], 1)
assert_eq("Snapshot keeps the saved collapse of a section not registered this session", partialSnap.collapsed.Gone, true)
assert_eq("Snapshot keeps the saved fold of a section not registered this session", partialSnap.folds and partialSnap.folds["Gone.f"], true)
assert_eq("Snapshot writes the current value of a registered item over the saved one", partialSnap.values["Sec.on"], true)
assert_eq("Snapshot writes the current dock over the saved one", partialSnap.dock, "left")
assert_eq("Snapshot leaves the kept snapshot unchanged", partial.persistSnapshot.values["Sec.on"], false)

-- A value cleared to nil is saved as cleared, so the item does not return to its default after a restart.
local cleared = NewState()
cleared.values["Sec.name"] = nil
cleared.values["Sec.on"] = true
local clearedSnap = Persist.Snapshot(cleared)
assert_eq("Snapshot records a cleared textinput", clearedSnap.cleared and clearedSnap.cleared["Sec.name"], true)
assert_eq("Snapshot does not record a value that is set", clearedSnap.cleared and clearedSnap.cleared["Sec.on"], nil)
local clearedFresh = NewState()
clearedFresh.values["Sec.name"] = "early"
local clearedKeys = Persist.Apply(clearedSnap, clearedFresh)
assert_eq("Apply clears a value the snapshot records as cleared", clearedFresh.values["Sec.name"], nil)
assert_eq("Apply returns the cleared keys so the seeds can respect them", clearedKeys, { "Sec.name" })

-- The store keeps the host's own key beside __modmenu, on disk as well as in memory.
RemoveTemp()
Store.Init({ id = "ModMenuPersistSpec", file = tmp })
Store.Set("x", 7)
Store.Set("__modmenu", snap)
Store.Init({ id = "ModMenuPersistSpec", file = tmp })
assert_eq("Set __modmenu leaves the host key x intact", Store.Get("x"), 7)
local loaded = Store.Get("__modmenu")
assert_eq("Get __modmenu values Sec.on is true", loaded and loaded.values and loaded.values["Sec.on"], true)

-- Apply onto a fresh state replaces the author defaults with the snapshot.
local fresh = NewState("right", "A")
fresh.values["Sec.on"] = false
Persist.Apply(loaded, fresh)
assert_eq("Apply dock", fresh.config.dock, "left")
assert_eq("Apply tab", fresh.activeTab, "B")
assert_eq("Apply value over the default", fresh.values["Sec.on"], true)
assert_eq("Apply value inside a row", fresh.values["Sec.count"], 3)
assert_eq("Apply value inside a fold", fresh.values["Sec.name"], "Ann")
assert_eq("Apply section collapse", fresh.collapsedById["Sec"], true)
assert_eq("Apply fold collapse", fresh.foldCollapsedByKey["Sec.more"], false)

-- A snapshot value for an item that no longer exists, and an unknown tab or dock, are ignored.
local stale = NewState("top", "A")
Persist.Apply({
    dock = "sideways",
    tab = "Removed",
    collapsed = { Other = true, Gone = true },
    values = { ["Gone.old"] = 1, ["Sec.run"] = "x", ["Sec.on"] = { nested = true } },
}, stale)
assert_eq("Apply ignores an unknown dock", stale.config.dock, "top")
assert_eq("Apply ignores a tab that Init does not list", stale.activeTab, "A")
assert_eq("Apply ignores a value for a missing item", stale.values["Gone.old"], nil)
assert_eq("Apply ignores a value for an item without a value", stale.values["Sec.run"], nil)
assert_eq("Apply ignores a value that is not a scalar", stale.values["Sec.on"], nil)
assert_eq("Apply ignores collapse for a section that is not collapsible", stale.collapsedById["Other"], nil)
assert_eq("Apply ignores collapse for a missing section", stale.collapsedById["Gone"], nil)
assert_true("Apply ignores a snapshot that is not a table", pcall(Persist.Apply, "junk", NewState()))

-- A saved value whose type does not match its item is ignored, so the item keeps its current value.
local typed = NewState()
typed.sections[1].items[5] = { type = "slider", id = "vol", label = "Vol", min = 0, max = 10 }
typed.sections[1].items[6] = { type = "dropdown", id = "pick", label = "Pick", options = { "a" } }
typed.values["Sec.on"] = false
typed.values["Sec.count"] = 2
typed.values["Sec.name"] = "Bo"
typed.values["Sec.vol"] = 4
typed.values["Sec.pick"] = "a"
Persist.Apply({
    values = {
        ["Sec.on"] = "yes",
        ["Sec.count"] = "3",
        ["Sec.name"] = 5,
        ["Sec.vol"] = true,
        ["Sec.pick"] = 1,
    },
}, typed)
assert_eq("Apply ignores a checkbox value that is not a boolean", typed.values["Sec.on"], false)
assert_eq("Apply ignores a number value that is not a number", typed.values["Sec.count"], 2)
assert_eq("Apply ignores a textinput value that is not a string", typed.values["Sec.name"], "Bo")
assert_eq("Apply ignores a slider value that is not a number", typed.values["Sec.vol"], 4)
assert_eq("Apply ignores a dropdown value that is not a string", typed.values["Sec.pick"], "a")

-- A section registered after Apply gets its part once, so a later Register keeps the player's changes.
local late = NewState("right", "A")
local lateSections = late.sections
late.sections = {}
Persist.Apply({ values = { ["Sec.on"] = true } }, late)
assert_eq("Apply leaves a section that is not registered yet alone", late.values["Sec.on"], nil)
late.sections = lateSections
Persist.ApplySection(late, lateSections[1])
assert_eq("ApplySection applies the kept snapshot on the first Register", late.values["Sec.on"], true)
late.values["Sec.on"] = false
Persist.ApplySection(late, lateSections[1])
assert_eq("ApplySection does not apply the snapshot twice", late.values["Sec.on"], false)

-- Schedule writes once, 300 ms after the last change, and never on a tick before that.
local now = 0
local clockBefore = Persist._clock
Persist._clock = function()
    return now
end
local writes = {}
local fakeStore = {
    Set = function(key, value)
        writes[#writes + 1] = { key = key, value = value }
        return true
    end,
}
local count = 0
local function SnapshotFn()
    count = count + 1
    return { n = count }
end
Persist.Schedule(fakeStore, SnapshotFn, 300)
now = 0.1
assert_eq("Flush before 300 ms writes nothing", Persist.Flush(), false)
now = 0.2
Persist.Schedule(fakeStore, SnapshotFn, 300)
now = 0.4
assert_eq("Flush 200 ms after the last change writes nothing", Persist.Flush(), false)
assert_eq("no write before the debounce ends", #writes, 0)
assert_true("a write is pending", Persist.Pending())
now = 0.5
assert_eq("Flush 300 ms after the last change writes", Persist.Flush(), true)
assert_eq("one write after the debounce", #writes, 1)
assert_eq("the write uses the reserved key", writes[1] and writes[1].key, "__modmenu")
assert_eq("the snapshot is taken once, at write time", count, 1)
now = 2
assert_eq("Flush with nothing pending writes nothing", Persist.Flush(), false)
assert_eq("still one write", #writes, 1)
assert_true("nothing is pending after the write", not Persist.Pending())

-- Cancel drops the pending write, so turning autosave off within the debounce writes nothing.
Persist.Schedule(fakeStore, SnapshotFn, 300)
assert_true("Persist.Cancel is a function", type(Persist.Cancel) == "function")
if type(Persist.Cancel) == "function" then
    Persist.Cancel()
end
assert_true("nothing is pending after Cancel", not Persist.Pending())
assert_eq("a forced Flush after Cancel writes nothing", Persist.Flush(true), false)
assert_eq("still one write after Cancel", #writes, 1)

-- A store that raises does not break the shell. The error is logged and Flush reports no write.
local printBefore = print
local logged = {}
print = function(...)
    logged[#logged + 1] = table.concat({ ... }, " ")
end
Persist.Schedule({ Set = function()
    error("call Init first")
end }, SnapshotFn, 300)
now = 3
local flushedBroken = Persist.Flush()
print = printBefore
assert_eq("Flush with a failing store reports no write", flushedBroken, false)
assert_true("Flush with a failing store logs the error", #logged == 1 and logged[1]:find("call Init first", 1, true) ~= nil)
Persist._clock = clockBefore

-- The snapshot is JSON-safe, so the store accepts it.
assert_true("Snapshot is JSON-safe", Json.IsSafe(snap))

RemoveTemp()
