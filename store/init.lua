--[[
  ModMenu.store — host-owned JSON key/value store.

  Public name is ModMenu.ConfigManager (facade + ConfigManager.lua shim):

    local ModMenu = require("ModMenu.ModMenu")
    local ConfigManager = ModMenu.ConfigManager
    -- or: require("ModMenu.ConfigManager") / require("ModMenu.core.store")

    ConfigManager.Init({
        id = "MyMod",
        defaults = { volume = 1 },
    })
    ConfigManager.Get("volume")
    ConfigManager.Set("volume", 0.5)  -- writes Mods/MyMod/config.json

  JSON-safe values only (bool, number, string, table, nil). Hosts still own
  when to Set and how to apply. Unknown file keys are kept.
  This module must not require ModMenu.ModMenu (no cycle).
]]

local Json = require("ModMenu.store.json")
local Paths = require("ModMenu.store.paths")

local M = {}

--- Rename a file. This is a module field so that a spec can replace it with a failing stub.
M._rename = os.rename

local LIB_NAME = "ConfigManager"

local initialized = false
local modId = nil
local filePath = nil
local autosave = true
local defaults = {}
local store = {}
local loadFailed = false
-- True while `.tmp` holds the only copy of a newer config, because copying it to `.bad`
-- failed. Overwrite refuses while this is true.
local tmpUncopied = false
-- True while the config file that failed to parse has no copy at `.bad`, because the copy
-- failed. Overwrite refuses while this is true, because its save replaces that file.
local badUncopied = false

local function Log(msg)
    print(string.format("[%s] %s\n", LIB_NAME, tostring(msg)))
end

---@param value any
---@param seen table|nil
---@return any
local function Copy(value, seen)
    -- The JSON null sentinel is returned as it is, because a copy would be a plain empty table
    -- that Encode writes as `{}` instead of `null`.
    if type(value) ~= "table" or value == Json.null then
        return value
    end
    seen = seen or {}
    if seen[value] then
        error(LIB_NAME .. ": circular table")
    end
    seen[value] = true
    local out = {}
    for k, v in pairs(value) do
        out[Copy(k, seen)] = Copy(v, seen)
    end
    seen[value] = nil
    return out
end

---@param a any
---@param b any
---@return boolean
local function Equal(a, b)
    if a == b then
        return true
    end
    -- The JSON null sentinel is an empty table, so the walk below would find it equal to `{}`.
    -- It is equal only to itself, which the check above has already handled.
    if a == Json.null or b == Json.null then
        return false
    end
    if type(a) ~= type(b) or type(a) ~= "table" then
        return false
    end
    for k, v in pairs(a) do
        if not Equal(v, b[k]) then
            return false
        end
    end
    for k in pairs(b) do
        if a[k] == nil then
            return false
        end
    end
    return true
end

---@param path string
---@return table|nil, string|nil
local function ReadFile(path)
    local f, err = io.open(path, "r")
    if not f then
        return nil, err
    end
    local text = f:read("*a")
    f:close()
    if type(text) ~= "string" or text:match("^%s*$") then
        return {}
    end
    local ok, decoded = pcall(Json.DecodeObject, text)
    if not ok then
        return nil, tostring(decoded)
    end
    return decoded
end

--- Write the config through `<path>.tmp`. The third result is true when the old config was
--- moved to `.prev` and could not be moved back, so that nothing is at the path.
---@param path string
---@param text string
---@return boolean ok True when the new config is at the path.
---@return string|nil err The error from the step that failed.
---@return boolean|nil stranded True when both the replace and the rollback failed, so that the old config is only at `.prev` and the new one only at `.tmp`.
local function WriteFile(path, text)
    local tmp = path .. ".tmp"
    -- The config itself is never opened for writing, because opening it truncates it before
    -- the new text is on disk. A stale temporary file may block the open, so it is removed
    -- and the open is tried once more.
    local f, err = io.open(tmp, "w")
    if not f then
        os.remove(tmp)
        f, err = io.open(tmp, "w")
        if not f then
            return false, err
        end
    end

    -- A full disk can cut the text short, and a short file must never replace a whole one,
    -- so the results of the writes and the close are checked before the rename.
    local wrote, writeErr = f:write(text)
    if wrote and text:sub(-1) ~= "\n" then
        wrote, writeErr = f:write("\n")
    end
    local closed, closeErr = f:close()
    if not wrote or not closed then
        os.remove(tmp)
        return false, writeErr or closeErr
    end

    -- The old file is never removed before the new text is in place, so that a crash at any
    -- point leaves a whole config on disk. Between the two renames below the old config sits
    -- only at `.prev`, and Init moves it back when it finds no config at the path.
    local renamed, renameErr = M._rename(tmp, path)
    if renamed then
        return true
    end
    if not Paths.FileExists(path) then
        os.remove(tmp)
        return false, renameErr
    end

    -- On Windows a rename over an existing file can fail, so the old file is first moved
    -- aside to `.prev` and is moved back if the new file cannot take its place.
    local prev = path .. ".prev"
    os.remove(prev)
    local moved, moveErr = M._rename(path, prev)
    if not moved then
        os.remove(tmp)
        return false, moveErr
    end
    local replaced, replaceErr = M._rename(tmp, path)
    if not replaced then
        local restored, restoreErr = M._rename(prev, path)
        if not restored then
            -- Both copies are kept, because the old config is now only at `.prev` and the
            -- new one only at `.tmp`, and removing either would lose settings. The third
            -- result tells Save to refuse later saves and to copy `.tmp` to `.bad`, because
            -- the next save would truncate `.tmp`.
            Log(string.format("%s: could not move %s back to %s, because %s. The old config is at %s "
                .. "and the new config is at %s (saves refused until Overwrite).",
                tostring(modId), prev, path, tostring(restoreErr), prev, tmp))
            return false, replaceErr, true
        end
        os.remove(tmp)
        return false, replaceErr
    end
    -- A `.prev` left here is harmless, because Init restores it only when a `.tmp` sits beside
    -- it, but it is logged so that the user can remove the stale backup.
    local removed, removeErr = os.remove(prev)
    if not removed then
        Log(string.format("%s: could not remove the old config backup %s, because %s", tostring(modId), prev,
            tostring(removeErr)))
    end
    return true
end

local function EnsureInit()
    if not initialized then
        error(LIB_NAME .. ": call Init first")
    end
end

---@param path string
---@return string|nil
local function ReadBytes(path)
    local f = io.open(path, "rb")
    if not f then
        return nil
    end
    local bytes = f:read("*a")
    f:close()
    return bytes
end

--- Copy a config file the store cannot use to `<path>.bad`, so that the user can recover it.
--- The source is the config itself when it failed to parse, or `<path>.tmp` when it holds a
--- newer config that a failed restore left behind.
--- An existing copy is never replaced, because it may hold an earlier file the user still needs.
--- When `.bad` is taken by different bytes, the copy goes to the first free `<path>.bad.2`,
--- `<path>.bad.3` and so on. When any existing copy already holds the same bytes, nothing is
--- written, so that a file that stays broken does not add a copy on every launch, but the log
--- still names that copy, so that every launch tells the user where it is.
--- Returns true when the bytes are safe in a copy, or when the source does not exist and there
--- is nothing to keep. Returns false when the copy could not be written.
---@param path string
---@param source string|nil
---@param what string|nil
---@return boolean
local function KeepBadCopy(path, source, what)
    what = what or "the unparsed config"
    local bytes = ReadBytes(source or path)
    if bytes == nil then
        return true
    end
    local badPath = path .. ".bad"
    local n = 1
    while Paths.FileExists(badPath) do
        if ReadBytes(badPath) == bytes then
            Log(string.format("%s: %s is already copied at %s", modId, what, badPath))
            return true
        end
        n = n + 1
        badPath = string.format("%s.bad.%d", path, n)
    end
    local dst, err = io.open(badPath, "wb")
    if not dst then
        Log(string.format("%s: could not copy %s to %s, because %s", modId, what, badPath, tostring(err)))
        return false
    end
    local wrote, writeErr = dst:write(bytes)
    local closed, closeErr = dst:close()
    if not wrote or not closed then
        os.remove(badPath)
        Log(string.format("%s: could not copy %s to %s, because %s", modId, what, badPath,
            tostring(writeErr or closeErr)))
        return false
    end
    Log(string.format("%s: copied %s to %s", modId, what, badPath))
    return true
end

--- Copy the newer config at `<path>.tmp` to `.bad`, and record whether that copy is missing.
--- While it is missing, Overwrite refuses, because its save would truncate `.tmp`, the only
--- copy of the newer config.
---@return boolean
local function KeepNewerTmp()
    -- Init sets filePath before anything calls this, so the assert never fails and only narrows the type to string.
    local path = assert(filePath, LIB_NAME .. ": call Init first")
    local copied = KeepBadCopy(path, path .. ".tmp", "the newer config from " .. path .. ".tmp")
    tmpUncopied = not copied
    return copied
end

local function MergeLoaded(loaded)
    store = Copy(defaults)
    if type(loaded) ~= "table" then
        return
    end
    for k, v in pairs(loaded) do
        if type(k) == "string" then
            store[k] = Copy(v)
        end
    end
end

--- Initialize the store and load config.json if present. Safe to call again.
---@param opts { id: string, defaults?: table, file?: string, autosave?: boolean }
---@return table
function M.Init(opts)
    opts = opts or {}
    if type(opts.id) ~= "string" or opts.id == "" then
        error(LIB_NAME .. ".Init: id must be a non-empty string")
    end
    if opts.defaults ~= nil and type(opts.defaults) ~= "table" then
        error(LIB_NAME .. ".Init: defaults must be a table")
    end
    if opts.defaults ~= nil and not Json.IsSafe(opts.defaults) then
        error(LIB_NAME .. ".Init: defaults must be JSON-safe")
    end

    modId = opts.id
    autosave = opts.autosave ~= false
    defaults = Copy(opts.defaults or {})
    filePath = Paths.ResolveFile(modId, opts.file)
    loadFailed = false
    tmpUncopied = false
    badUncopied = false

    -- A crash between the two renames in WriteFile leaves the old config only at `.prev`, with
    -- the new one at `.tmp`. Only that pair marks such a crash. A `.prev` alone can be a stale
    -- backup, and restoring it would bring back old settings after the user deleted the config
    -- on purpose. When the pair is found, `.prev` is moved back before the read, so that the
    -- user's settings are not replaced by defaults on the next launch.
    local prevPath = filePath .. ".prev"
    if not Paths.FileExists(filePath) and Paths.FileExists(prevPath) and Paths.FileExists(filePath .. ".tmp") then
        local restored, restoreErr = M._rename(prevPath, filePath)
        if not restored then
            -- The store refuses to save until the host calls Overwrite, because a save writes
            -- through `.tmp` and truncates it, and `.tmp` holds the only copy of the newer
            -- config. That file is copied to `.bad` first, so that it stays recoverable after
            -- Overwrite. The older config stays at `.prev` only until a later save takes the
            -- move-aside path in WriteFile, which removes it.
            loadFailed = true
            MergeLoaded(nil)
            Log(string.format("%s: could not move %s back to %s, because %s (saves refused until Overwrite)",
                modId, prevPath, filePath, tostring(restoreErr)))
            KeepNewerTmp()
            initialized = true
            return M
        end
        Log(string.format("%s: moved %s back to %s", modId, prevPath, filePath))
        -- The old config is loaded, but `.tmp` holds the newer one, which was complete before
        -- the crash because WriteFile renames only after the write and the close succeed. It is
        -- copied to `.bad`, because the next save truncates `.tmp`. If the copy fails, saves
        -- are refused until Overwrite, so that the newer config is not lost without a word.
        if not KeepNewerTmp() then
            loadFailed = true
            Log(string.format("%s: saves refused until Overwrite, because %s.tmp could not be copied",
                modId, filePath))
        end
    end

    if Paths.FileExists(filePath) then
        local loaded, err = ReadFile(filePath)
        if loaded == nil then
            loadFailed = true
            MergeLoaded(nil)
            Log(string.format("%s: failed to parse %s — %s (file left untouched)", modId, filePath, tostring(err)))
            -- If the copy fails, Overwrite refuses until it succeeds, so that the unparsed file
            -- is not replaced while it is the only copy of the user's settings.
            badUncopied = not KeepBadCopy(filePath)
            initialized = true
            return M
        end
        MergeLoaded(loaded)
        Log(string.format("%s: loaded %s", modId, filePath))
    else
        MergeLoaded(nil)
        Log(string.format("%s: no config yet (%s)", modId, filePath))
    end
    initialized = true
    return M
end

---@return string|nil
function M.File()
    return filePath
end

--- Current value, or the Init default if unset. Tables are copies.
---@param key string
---@return any
function M.Get(key)
    EnsureInit()
    if type(key) ~= "string" or key == "" then
        error(LIB_NAME .. ".Get: key must be a non-empty string")
    end
    local value = store[key]
    if value == nil then
        value = defaults[key]
    end
    return Copy(value)
end

--- Write a key. nil removes it (Get then returns the default). Autosaves.
--- Returns true when the value is unchanged or was stored, and the result of Save when
--- autosave is on. While the config file failed to parse, Set keeps the value in memory,
--- writes nothing and returns false, until the host calls Overwrite.
---@param key string
---@param value any
---@return boolean
function M.Set(key, value)
    EnsureInit()
    if type(key) ~= "string" or key == "" then
        error(LIB_NAME .. ".Set: key must be a non-empty string")
    end
    if value ~= nil and not Json.IsSafe(value) then
        error(LIB_NAME .. ".Set: value must be JSON-safe")
    end

    -- The value is kept in memory even while the file failed to parse, so that Overwrite
    -- saves what the host set rather than only the defaults.
    if loadFailed then
        store[key] = Copy(value)
        return false
    end

    local current = store[key]
    if current == nil then
        current = defaults[key]
    end
    if Equal(current, value) then
        return true
    end

    if value == nil then
        store[key] = nil
    else
        store[key] = Copy(value)
    end
    if autosave then
        return M.Save()
    end
    return true
end

--- True when Init found a config file it could not parse, or when the old config sits at
--- `.prev` and could not be moved back, either by Init after a crash or by a save whose
--- rollback failed. While this is true, Set and Save write nothing, so that the user's files
--- are not replaced by defaults.
---@return boolean
function M.LoadFailed()
    return loadFailed
end

--- Replace a config file that failed to parse, or a config that a failed restore left at
--- `.prev` and `.tmp`, with the in-memory values. The host calls this once it has decided the
--- old file may be lost. A copy of the unparsed file, or of the newer config from `.tmp`,
--- remains at `<path>.bad`. After a failed restore the older config stays at `.prev` only
--- until a later save takes the move-aside path in WriteFile, which removes it.
--- Overwrite refuses and returns false while `.tmp` holds the only copy of a newer config,
--- because its save would truncate `.tmp`. It also refuses while the unparsed file has no
--- copy at `.bad`, because its save would replace that file. In both cases it tries the copy
--- to `.bad` again first.
---@return boolean
function M.Overwrite()
    EnsureInit()
    if tmpUncopied and not KeepNewerTmp() then
        Log(string.format("%s: refuse to overwrite, because %s.tmp holds the only copy of the newer config "
            .. "and it could not be copied to .bad", modId, filePath))
        return false
    end
    if badUncopied and filePath then
        badUncopied = not KeepBadCopy(filePath)
        if badUncopied then
            Log(string.format("%s: refuse to overwrite, because %s failed to parse and could not be copied "
                .. "to .bad", modId, filePath))
            return false
        end
    end
    loadFailed = false
    return M.Save()
end

--- Write the store to disk now. No-op if Init never loaded a path.
function M.Save()
    EnsureInit()
    if loadFailed then
        Log(string.format("%s: skip save, %s is not usable (it failed to parse, or the old config is stuck at .prev)",
            modId, filePath))
        return false
    end
    local out = {}
    for k, v in pairs(store) do
        out[k] = v
    end
    -- EnsureInit has passed, and Init sets filePath before it marks the store initialized,
    -- so the assert never fails and only narrows the type to string.
    local path = assert(filePath, LIB_NAME .. ": call Init first")
    local ok, err, stranded = WriteFile(path, Json.Encode(out, 0))
    if not ok then
        Log(string.format("%s: save failed %s — %s", modId, filePath, tostring(err)))
        if stranded then
            -- The files are now in the same state as after a failed restore in Init, with the
            -- old config only at `.prev` and the new one only at `.tmp`. Saves are refused
            -- until Overwrite, because the next save would truncate `.tmp`, and `.tmp` is
            -- copied to `.bad` so that the newer config survives Overwrite. If the copy fails,
            -- Overwrite refuses until a later try succeeds.
            loadFailed = true
            KeepNewerTmp()
        end
        return false
    end
    return true
end

return M
