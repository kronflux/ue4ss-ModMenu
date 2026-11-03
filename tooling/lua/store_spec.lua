local Store = require("ModMenu.core.store")

local tmp = (_REPO .. "/tooling/.tmp-store-spec.json"):gsub("\\", "/")

pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")
pcall(os.remove, tmp .. ".bad.3")

Store.Init({
    id = "ModMenuStoreSpec",
    file = tmp,
    defaults = {
        dock = "top",
        volume = 1,
        keybinds = { menuToggle = "F6" },
    },
})

assert_eq("Get default dock", Store.Get("dock"), "top")
assert_eq("Get default volume", Store.Get("volume"), 1)
assert_true("no file until first Set", io.open(tmp, "r") == nil)

Store.Set("dock", "right")
assert_eq("Get after Set", Store.Get("dock"), "right")

local f = io.open(tmp, "r")
assert_true("Set writes file", f ~= nil)
if f then
    local text = f:read("*a")
    f:close()
    assert_true("file contains dock", text:find('"dock"', 1, true) ~= nil)
    assert_true("file contains right", text:find('"right"', 1, true) ~= nil)
end

local binds = Store.Get("keybinds")
binds.menuToggle = "F8"
assert_eq("Get copies tables", Store.Get("keybinds").menuToggle, "F6")

Store.Set("dock", "right")
assert_eq("Set same value is no-op", Store.Get("dock"), "right")

pcall(os.remove, tmp)
local bad = io.open(tmp, "w")
bad:write("{")
bad:close()

Store.Init({
    id = "ModMenuStoreSpec",
    file = tmp,
    defaults = { dock = "top" },
})
assert_eq("bad JSON uses default", Store.Get("dock"), "top")

local leftover = io.open(tmp, "r")
local leftoverText = leftover:read("*a")
leftover:close()
assert_eq("bad JSON left untouched", leftoverText, "{")

pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".bad")

-- Set after a failed parse writes nothing and returns false.
-- The store must keep a file it could not parse, so that the user's settings are not lost,
-- until the host calls Overwrite.
local Json = require("ModMenu.store.json")
local badBytes = "{ not json"
local badFile = io.open(tmp, "wb")
badFile:write(badBytes)
badFile:close()

Store.Init({
    id = "ModMenuStoreSpec",
    file = tmp,
})

local function ReadBytes(path)
    local handle = io.open(path, "rb")
    if not handle then
        return nil
    end
    local bytes = handle:read("*a")
    handle:close()
    return bytes
end

assert_eq("failed parse leaves the file bytes unchanged", ReadBytes(tmp), badBytes)
assert_eq("failed parse copies the file to .bad", ReadBytes(tmp .. ".bad"), badBytes)
assert_eq("Set after a failed parse returns false", Store.Set("x", 1), false)
assert_eq("Set after a failed parse writes nothing", ReadBytes(tmp), badBytes)
assert_eq("Set of an unchanged value after a failed parse returns false", Store.Set("x", 1), false)
assert_eq("LoadFailed is true after a failed parse", Store.LoadFailed(), true)
assert_eq("Overwrite saves and returns true", Store.Overwrite(), true)
assert_eq("LoadFailed is false after Overwrite", Store.LoadFailed(), false)
local overwritten = ReadBytes(tmp)
assert_eq("Overwrite writes the in-memory table", overwritten and Json.DecodeObject(overwritten), { x = 1 })

assert_eq("Set of a changed value returns true", Store.Set("x", 2), true)
assert_eq("Set of an unchanged value returns true", Store.Set("x", 2), true)
local changed = ReadBytes(tmp)
assert_eq("Set of a changed value writes it", changed and Json.DecodeObject(changed), { x = 2 })

-- A second, different corruption must get its own copy, because .bad still holds the first.
local secondBytes = "{ still not json"
local secondFile = io.open(tmp, "wb")
secondFile:write(secondBytes)
secondFile:close()
Store.Init({ id = "ModMenuStoreSpec", file = tmp })
assert_eq("a second bad file leaves .bad unchanged", ReadBytes(tmp .. ".bad"), badBytes)
assert_eq("a second bad file is copied to .bad.2", ReadBytes(tmp .. ".bad.2"), secondBytes)

-- The same broken file on a later launch must not add another copy, and the log must still
-- name the copy that already holds it, so that every launch tells the user where it is.
local sameLogged = {}
local printBeforeSame = print
print = function(...)
    sameLogged[#sameLogged + 1] = table.concat({ ... }, " ")
end
Store.Init({ id = "ModMenuStoreSpec", file = tmp })
print = printBeforeSame
assert_eq("the same bad file adds no .bad.3", ReadBytes(tmp .. ".bad.3"), nil)
local namesExisting = false
for i = 1, #sameLogged do
    if sameLogged[i]:find(tmp .. ".bad.2", 1, true) then
        namesExisting = true
    end
end
assert_true("the same bad file logs the existing copy at .bad.2", namesExisting)

pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")
pcall(os.remove, tmp .. ".bad.3")

-- A failed rename must leave the old config intact, because the save writes a temporary
-- file first and only renames it over the config once the whole text is on disk.
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".prev")
local oldBytes = '{ "x": 1 }\n'
local oldFile = io.open(tmp, "wb")
oldFile:write(oldBytes)
oldFile:close()
Store.Init({ id = "ModMenuStoreSpec", file = tmp })

local realRename = Store._rename
Store._rename = function()
    return nil, "stub"
end
local setOk, setResult = pcall(Store.Set, "x", 2)
Store._rename = realRename

assert_true("Set with a failing rename does not raise", setOk)
assert_eq("a failed rename makes Set return false", setResult, false)
assert_eq("a failed rename leaves the old config intact", ReadBytes(tmp), oldBytes)
assert_eq("a failed rename leaves no .tmp", ReadBytes(tmp .. ".tmp"), nil)
assert_eq("a failed rename leaves no .prev", ReadBytes(tmp .. ".prev"), nil)

-- With the real rename, Save must replace the old config, even where a rename over an
-- existing file fails, and must leave no temporary file behind.
assert_eq("Save with the real rename returns true", Store.Save(), true)
local replaced = ReadBytes(tmp)
assert_eq("Save with the real rename replaces the content", replaced and Json.DecodeObject(replaced), { x = 2 })
assert_eq("Save with the real rename leaves no .tmp", ReadBytes(tmp .. ".tmp"), nil)
assert_eq("Save with the real rename leaves no .prev", ReadBytes(tmp .. ".prev"), nil)

-- When the old config has been moved to `.prev` and the new file then fails to take its
-- place, the old config must be moved back, so that the user keeps their settings.
-- The stub fails every rename of the temporary file, so that the move-aside step runs even
-- where a rename over an existing file would succeed, and passes the other renames through.
pcall(os.remove, tmp)
oldFile = io.open(tmp, "wb")
oldFile:write(oldBytes)
oldFile:close()
Store.Init({ id = "ModMenuStoreSpec", file = tmp })

local renames = 0
Store._rename = function(from, to)
    renames = renames + 1
    if from == tmp .. ".tmp" then
        return nil, "stub"
    end
    return realRename(from, to)
end
local rollbackOk, rollbackResult = pcall(Store.Set, "x", 3)
Store._rename = realRename

assert_true("Set with a failing replace does not raise", rollbackOk)
assert_eq("a failing replace makes Set return false", rollbackResult, false)
assert_eq("a failing replace runs the move-aside and the rollback", renames, 4)
assert_eq("a failing replace moves the old bytes back", ReadBytes(tmp), oldBytes)
assert_eq("a failing replace leaves no .prev", ReadBytes(tmp .. ".prev"), nil)
assert_eq("a failing replace leaves no .tmp", ReadBytes(tmp .. ".tmp"), nil)

-- When the rollback also fails, the old config is only at `.prev` and the new one only at
-- `.tmp`, so both must be kept. The store must then refuse to save until Overwrite, because a
-- later save would truncate `.tmp`, and it must copy `.tmp` to `.bad` so that the newer config
-- survives Overwrite.
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")
local strandedRenames = 0
Store._rename = function(from, to)
    strandedRenames = strandedRenames + 1
    if from == tmp .. ".tmp" or from == tmp .. ".prev" then
        return nil, "stub"
    end
    return realRename(from, to)
end
local keepOk, keepResult = pcall(Store.Set, "x", 4)
local renamesAfterFirstSet = strandedRenames
local secondOk, secondResult = pcall(Store.Set, "x", 5)
local renamesAfterSecondSet = strandedRenames
Store._rename = realRename

assert_true("Set with a failing rollback does not raise", keepOk)
assert_eq("a failing rollback makes Set return false", keepResult, false)
assert_eq("a failing rollback runs all four renames", renamesAfterFirstSet, 4)
assert_true("a second Set after a failing rollback does not raise", secondOk)
assert_eq("a second Set after a failing rollback returns false", secondResult, false)
assert_eq("a second Set after a failing rollback renames nothing", renamesAfterSecondSet, renamesAfterFirstSet)
assert_eq("a failing rollback sets LoadFailed", Store.LoadFailed(), true)
assert_eq("a failing rollback keeps the old bytes at .prev", ReadBytes(tmp .. ".prev"), oldBytes)
local keptNew = ReadBytes(tmp .. ".tmp")
assert_eq("a failing rollback keeps the new config at .tmp", keptNew and Json.DecodeObject(keptNew), { x = 4 })
local keptBad = ReadBytes(tmp .. ".bad")
assert_eq("a failing rollback copies the new config to .bad", keptBad and Json.DecodeObject(keptBad), { x = 4 })
assert_eq("Overwrite after a failing rollback returns true", Store.Overwrite(), true)
local overwrittenConfig = ReadBytes(tmp)
assert_eq("Overwrite after a failing rollback writes the in-memory values",
    overwrittenConfig and Json.DecodeObject(overwrittenConfig), { x = 5 })
assert_eq("Overwrite after a failing rollback leaves .prev untouched", ReadBytes(tmp .. ".prev"), oldBytes)
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".prev")
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")

-- When the rollback fails and the newer config cannot be copied to `.bad`, Overwrite must
-- refuse, because its save would truncate `.tmp`, the only copy of the newer config. Once the
-- copy succeeds, Overwrite must go ahead.
local realOpen = io.open
local function FailBadOpen(path, mode)
    if type(path) == "string" and path:find("%.bad[%.%d]*$") then
        return nil, "stub"
    end
    return realOpen(path, mode)
end
Store._rename = function(from, to)
    if from == tmp .. ".tmp" or from == tmp .. ".prev" then
        return nil, "stub"
    end
    return realRename(from, to)
end
io.open = FailBadOpen
local uncopiedOk, uncopiedResult = pcall(Store.Set, "x", 6)
Store._rename = realRename
local refusedOk, refusedResult = pcall(Store.Overwrite)
io.open = realOpen
local uncopiedTmp = ReadBytes(tmp .. ".tmp")

assert_true("Set with a failing rollback and a failing copy does not raise", uncopiedOk)
assert_eq("Set with a failing rollback and a failing copy returns false", uncopiedResult, false)
assert_true("Overwrite with an uncopied .tmp does not raise", refusedOk)
assert_eq("Overwrite with an uncopied .tmp returns false", refusedResult, false)
assert_eq("Overwrite with an uncopied .tmp keeps its bytes", uncopiedTmp and Json.DecodeObject(uncopiedTmp), { x = 6 })
assert_eq("Overwrite with an uncopied .tmp keeps LoadFailed", Store.LoadFailed(), true)
assert_eq("Overwrite goes ahead once the copy succeeds", Store.Overwrite(), true)
local lateBad = ReadBytes(tmp .. ".bad")
assert_eq("Overwrite copies the newer config to .bad first", lateBad and Json.DecodeObject(lateBad), { x = 6 })
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".prev")
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")

local function WriteBytes(path, bytes)
    local handle = io.open(path, "wb")
    handle:write(bytes)
    handle:close()
end

-- A crash between the two renames leaves the old config only at `.prev`, with the new one
-- still at `.tmp`. Init must move `.prev` back and load it, so that the next launch does not
-- start from defaults, and must copy `.tmp` to `.bad`, because the next save truncates it.
pcall(os.remove, tmp)
WriteBytes(tmp .. ".prev", '{ "dock": "left" }\n')
WriteBytes(tmp .. ".tmp", '{ "dock": "right" }\n')
Store.Init({ id = "ModMenuStoreSpec", file = tmp, defaults = { dock = "top" } })
assert_eq("Init loads a config left at .prev", Store.Get("dock"), "left")
assert_eq("Init leaves no .prev", ReadBytes(tmp .. ".prev"), nil)
assert_eq("Init moves .prev back to the config path", ReadBytes(tmp), '{ "dock": "left" }\n')
assert_eq("Init copies the newer config from .tmp to .bad", ReadBytes(tmp .. ".bad"), '{ "dock": "right" }\n')
pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".bad")

-- A `.prev` without a `.tmp` is a stale backup, for example when the final remove failed, and
-- the user may have deleted the config on purpose, so Init must not bring it back.
WriteBytes(tmp .. ".prev", '{ "dock": "left" }\n')
Store.Init({ id = "ModMenuStoreSpec", file = tmp, defaults = { dock = "top" } })
assert_eq("Init ignores a .prev alone", Store.Get("dock"), "top")
assert_eq("Init does not restore a .prev alone", ReadBytes(tmp), nil)
pcall(os.remove, tmp .. ".prev")

-- When the restore fails, the store must refuse to save, because a save writes through `.tmp`,
-- which then holds the only copy of the newer config.
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")
local newerBytes = '{ "dock": "right" }\n'
WriteBytes(tmp .. ".prev", '{ "dock": "left" }\n')
WriteBytes(tmp .. ".tmp", newerBytes)
local logged = {}
local realPrint = print
print = function(...)
    logged[#logged + 1] = table.concat({ ... }, " ")
end
Store._rename = function()
    return nil, "stub"
end
local restoreOk = pcall(Store.Init, { id = "ModMenuStoreSpec", file = tmp, defaults = { dock = "top" } })
Store._rename = realRename
print = realPrint
assert_true("Init with a failing restore does not raise", restoreOk)
assert_eq("a failing restore sets LoadFailed", Store.LoadFailed(), true)
assert_eq("Set after a failing restore returns false", Store.Set("dock", "bottom"), false)
assert_eq("Set after a failing restore leaves .tmp unchanged", ReadBytes(tmp .. ".tmp"), newerBytes)
assert_eq("Set after a failing restore creates no config", ReadBytes(tmp), nil)

-- Overwrite after a failed restore must leave the newer config recoverable at a path the log
-- names, because the save truncates `.tmp` before it writes the in-memory values.
assert_eq("Overwrite after a failing restore returns true", Store.Overwrite(), true)
local namesTmp = tmp:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
local recovered = false
for i = 1, #logged do
    for named in logged[i]:gmatch("(" .. namesTmp .. "[%w%.]*)") do
        named = named:gsub("%.$", "")
        if named ~= tmp .. ".tmp" and ReadBytes(named) == newerBytes then
            recovered = true
        end
    end
end
assert_true("Overwrite after a failing restore leaves the newer config at a logged path", recovered)

pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".prev")
pcall(os.remove, tmp .. ".bad")
pcall(os.remove, tmp .. ".bad.2")

-- When a config fails to parse and its copy to `.bad` fails, Overwrite must refuse, because it
-- would replace the only copy of the user's file. Once the copy succeeds, Overwrite must go
-- ahead.
local unparsedBytes = "{ broken"
WriteBytes(tmp, unparsedBytes)
io.open = FailBadOpen
local parseInitOk = pcall(Store.Init, { id = "ModMenuStoreSpec", file = tmp })
local parseLoadFailed = Store.LoadFailed()
local parseRefusedOk, parseRefused = pcall(Store.Overwrite)
io.open = realOpen
assert_true("Init with an unparsed config and a failing copy does not raise", parseInitOk)
assert_eq("an unparsed config with a failing copy sets LoadFailed", parseLoadFailed, true)
assert_eq("a refused Overwrite keeps LoadFailed", Store.LoadFailed(), true)
assert_true("Overwrite with an uncopied unparsed config does not raise", parseRefusedOk)
assert_eq("Overwrite with an uncopied unparsed config returns false", parseRefused, false)
assert_eq("Overwrite with an uncopied unparsed config keeps its bytes", ReadBytes(tmp), unparsedBytes)
assert_eq("Overwrite goes ahead once the unparsed config is copied", Store.Overwrite(), true)
assert_eq("Overwrite copies the unparsed config to .bad first", ReadBytes(tmp .. ".bad"), unparsedBytes)
pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".bad")

-- When the restore after a crash succeeds and the copy of `.tmp` to `.bad` fails, the store
-- must refuse to save, because the next save would truncate `.tmp`, the only copy of the
-- newer config. The restored config must still load.
WriteBytes(tmp .. ".prev", '{ "dock": "left" }\n')
WriteBytes(tmp .. ".tmp", newerBytes)
io.open = FailBadOpen
local restoredInitOk = pcall(Store.Init, { id = "ModMenuStoreSpec", file = tmp, defaults = { dock = "top" } })
io.open = realOpen
assert_true("Init with a restore and a failing copy does not raise", restoredInitOk)
assert_eq("a restore with a failing copy sets LoadFailed", Store.LoadFailed(), true)
assert_eq("a restore with a failing copy loads the restored config", Store.Get("dock"), "left")
assert_eq("a restore with a failing copy keeps the .tmp bytes", ReadBytes(tmp .. ".tmp"), newerBytes)
assert_eq("Set after a restore with a failing copy returns false", Store.Set("dock", "bottom"), false)
assert_eq("Set after a restore with a failing copy leaves .tmp unchanged", ReadBytes(tmp .. ".tmp"), newerBytes)
pcall(os.remove, tmp)
pcall(os.remove, tmp .. ".tmp")
pcall(os.remove, tmp .. ".prev")
pcall(os.remove, tmp .. ".bad")

-- A JSON null inside a stored array must be saved as null, because Copy once turned the
-- sentinel into a new empty table that was saved as `{}`.
Store.Init({ id = "ModMenuStoreSpec", file = tmp })
assert_eq("Set of an array with a null returns true", Store.Set("list", { 1, Json.null, 3 }), true)
assert_eq("Save of an array with a null returns true", Store.Save(), true)
local nullBytes = ReadBytes(tmp) or ""
assert_true("the saved file holds null", nullBytes:find("null", 1, true) ~= nil)
assert_true("the saved file holds no {}", nullBytes:find("{}", 1, true) == nil)
local list = Store.Get("list")
assert_true("Get returns the null sentinel at index 2", list ~= nil and list[2] == Json.null)

-- The sentinel is an empty table, so a plain comparison finds it equal to `{}`. Set must see
-- the swap from null to `{}` as a change, or the new value is never stored or saved.
local beforeSwap = ReadBytes(tmp)
assert_eq("Set of {} in place of null returns true", Store.Set("list", { 1, {}, 3 }), true)
local swapped = Store.Get("list")
assert_true("Set of {} in place of null stores the change", swapped ~= nil and swapped[2] ~= Json.null
    and type(swapped[2]) == "table")
assert_true("Set of {} in place of null saves the change", ReadBytes(tmp) ~= beforeSwap)
pcall(os.remove, tmp)

local viaShim = require("ModMenu.ConfigManager")
local viaCore = require("ModMenu.core.store")
local viaStore = require("ModMenu.store.init")
assert_true("ConfigManager shim is store.init", viaShim == viaStore)
assert_true("core.store shim is store.init", viaCore == viaStore)
assert_true("ConfigManager.Get exists", type(viaShim.Get) == "function")
assert_true("ConfigManager.Set exists", type(viaShim.Set) == "function")
assert_true("ConfigManager.Save exists", type(viaShim.Save) == "function")
assert_true("ConfigManager.File exists", type(viaShim.File) == "function")
