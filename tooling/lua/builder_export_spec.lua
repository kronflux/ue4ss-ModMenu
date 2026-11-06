-- The builder writes Lua that a menu author runs. These cases run that Lua, as written by the builder, and
-- hand what it passes to ModMenu.Init and ModMenu.Register to the library's own checks: Config.ApplyInit for
-- the Init options and Registry.Register for every section, which runs each widget's validate. A field the
-- builder writes that the library rejects fails here, and so does a field the library no longer reads.
--
-- The two files are written by builder/src/export/lua.test.ts from the builder's full document and its host
-- fixture. Regenerate them there, with `npx vitest run -u` in builder/.
-- The registry requires UEHelpers through the shell build module, so an empty stub stands in while it loads.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okConfig, Config = pcall(require, "ModMenu.core.config")
local okRegistry, Registry = pcall(require, "ModMenu.shell.registry")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("core.config loads under MoonSharp", okConfig)
assert_true("shell.registry loads under MoonSharp", okRegistry)
if not (okConfig and okRegistry) then
    return
end

local function readFile(name)
    local f = io.open(_REPO .. "/tooling/lua/fixtures/" .. name, "r")
    if f == nil then
        return nil
    end
    local text = f:read("*a")
    f:close()
    return text
end

--- Run an exported script with a fake ModMenu that records what it was given.
--- @return table|nil init, table sections, string|nil error
local function runExport(text)
    local captured = { init = nil, sections = {} }
    local fake = {
        Init = function(opts)
            captured.init = opts
        end,
        Register = function(section)
            captured.sections[#captured.sections + 1] = section
        end,
    }
    local env = {
        require = function(name)
            if name == "ModMenu.ModMenu" then
                return fake
            end
            error("the export required " .. tostring(name))
        end,
        print = function() end,
        -- Key.F8 and the like become their own name, which is all Init reads of the key here.
        Key = setmetatable({}, {
            __index = function(_, name)
                return name
            end,
        }),
    }
    local chunk, loadErr = load(text, "builder export", "t", env)
    if chunk == nil then
        return nil, {}, tostring(loadErr)
    end
    local ok, err = pcall(chunk)
    if not ok then
        return nil, {}, tostring(err)
    end
    return captured.init, captured.sections, nil
end

--- A closed menu with nothing built, so Register runs its validation and seeding and touches no UMG.
local function newState(config)
    return {
        config = config,
        values = {},
        liveControls = {},
        itemNodes = {},
        sections = {},
        sectionIndexById = {},
        collapsedById = {},
        foldCollapsedByKey = {},
        menuOpen = false,
        makeWidgetCtx = function()
            return {}
        end,
    }
end

local function checkExport(label, fileName, expectedSections)
    local text = readFile(fileName)
    assert_true(label .. ": the fixture file exists", text ~= nil)
    if text == nil then
        return
    end
    local init, sections, runErr = runExport(text)
    assert_true(label .. ": the exported script runs (" .. tostring(runErr) .. ")", runErr == nil)
    if runErr ~= nil then
        return
    end
    assert_true(label .. ": the script calls ModMenu.Init", init ~= nil)
    assert_eq(label .. ": the script registers every section", #sections, expectedSections)

    local config = Config.New()
    config.key = 1
    config.keyHint = "F6"
    local okInit, initErr = pcall(Config.ApplyInit, config, init, { instanceUnlocked = true })
    assert_true(label .. ": Config.ApplyInit accepts the Init options (" .. tostring(initErr) .. ")", okInit)

    local state = newState(config)
    for _, section in ipairs(sections) do
        local okReg, regErr = pcall(Registry.Register, state, section)
        assert_true(
            label .. ": Registry.Register accepts section " .. tostring(section.id) .. " (" .. tostring(regErr) .. ")",
            okReg
        )
    end
    return init, sections, config, state
end

-- The host fixture is the builder's shipped example.
checkExport("host fixture", "builder_host_export.lua", 7)

-- The full document sets every optional field of every type, so each one reaches the widget's validate.
local init, sections, config = checkExport("full document", "builder_full_export.lua", 2)
if init ~= nil and config ~= nil then
    assert_eq("Init passes tooltipDelayMs to the config", config.tooltipDelayMs, 250)
    assert_eq("Init passes showClose to the config", config.showClose, false)
    assert_eq("Init passes cursorScale to the config", config.cursorScale, 2)
    assert_eq("Init passes a spacing token to the config", config.spacing.gapItem, 4)
    assert_eq("Init passes the last spacing token to the config", config.spacing.panelPad, 10)
    assert_eq("Init passes the tabs to the config", config.tabs, { "Main", "Other" })

    local all = sections[1]
    assert_eq("the section keeps its description", all.description, "One line under the title")
    assert_eq("the section keeps its prefix", all.prefix, "[all]")
    local byId = {}
    local function index(items)
        for _, item in ipairs(items) do
            if item.id ~= nil then
                byId[item.id] = item
            end
            if item.items ~= nil then
                index(item.items)
            end
        end
    end
    index(all.items)
    assert_eq("a label keeps align", byId.note.align, "center")
    assert_eq("a label keeps style", byId.note.style, "heading")
    assert_eq("a label keeps wrap false", byId.note.wrap, false)
    assert_eq("a label keeps enabled false", byId.note.enabled, false)
    assert_eq("a number keeps step", byId.num.step, 0.5)
    assert_eq("a number keeps prefix", byId.num.prefix, "$")
    assert_eq("a number keeps debounceMs", byId.num.debounceMs, 100)
    assert_eq("a slider keeps showValue false", byId.sld.showValue, false)
    assert_eq("a slider keeps labelWidth", byId.sld.labelWidth, 100)
    assert_eq("a stepper keeps min", byId.stp.min, 0)
    assert_eq("a stepper keeps max", byId.stp.max, 10)
    assert_eq("a stepper keeps step", byId.stp.step, 2)
    assert_eq("a stepper keeps default", byId.stp.default, 4)
    assert_eq("a stepper keeps integer", byId.stp.integer, true)
    assert_eq("a stepper keeps format", byId.stp.format, "%d pcs")
    assert_eq("a stepper keeps enabled false", byId.stp.enabled, false)
    assert_eq("a stepper in a row keeps its step", byId.rowStp.step, 0.5)
    assert_eq("a stepper in a fold keeps its max", byId.foldStp.max, 3)
    assert_eq("a progress bar keeps min", byId.prg.min, 0)
    assert_eq("a progress bar keeps max", byId.prg.max, 200)
    assert_eq("a progress bar keeps default", byId.prg.default, 50)
    assert_eq("a progress bar keeps format", byId.prg.format, "%d of 200")
    assert_eq("a progress bar keeps variant", byId.prg.variant, "success")
    assert_eq("a progress bar keeps enabled false", byId.prg.enabled, false)
    assert_eq("a progress bar has no onChange", byId.prg.onChange, nil)
    assert_eq("a progress bar in a row keeps its max and variant", byId.rowPrg.max .. byId.rowPrg.variant, "5danger")
    assert_eq("a progress bar in a fold keeps its default", byId.foldPrg.default, 0.25)
    assert_eq("a multiselect keeps its options", #byId.mul.options, 3)
    assert_eq("a multiselect keeps its default array", byId.mul.default, { "a", "c" })
    assert_eq("a multiselect keeps columns", byId.mul.columns, 2)
    assert_eq("a multiselect keeps enabled false", byId.mul.enabled, false)
    assert_eq("a multiselect keeps its tooltip", byId.mul.tooltip, "Multiselect tip")
    assert_eq("a multiselect in a fold keeps its default", byId.foldMul.default, { "q" })
    assert_eq("a multiselect in a fold keeps columns", byId.foldMul.columns, 4)
    assert_eq("a colorpicker keeps its default colour", byId.col.default, { R = 0.25, G = 0.5, B = 0.75, A = 0.5 })
    assert_eq("a colorpicker keeps alpha false", byId.col.alpha, false)
    assert_eq("a colorpicker keeps enabled false", byId.col.enabled, false)
    assert_eq("a colorpicker keeps its tooltip", byId.col.tooltip, "Colorpicker tip")
    assert_eq("a colorpicker in a fold keeps its default", byId.foldCol.default, { R = 1, G = 0, B = 0, A = 1 })
    assert_eq("a colorpicker in a fold leaves alpha unset", byId.foldCol.alpha, nil)
    assert_eq("a checkbox keeps showState false",byId.chk.showState, false)
    assert_eq("a dropdown keeps maxVisible", byId.drop.maxVisible, 5)
    assert_eq("a dropdown keeps allowEmpty", byId.drop.allowEmpty, true)
    assert_eq("a confirm keeps cancelLabel", byId.go.confirm.cancelLabel, "No")
    assert_eq("a confirm keeps its variant", byId.go.confirm.variant, "success")
    assert_eq("a fold keeps visible true as a field it did not write", byId.fold.visible, nil)
end

-- The AC-11 document: theme storm, the button borrowed from neon, a toggle colour and one button's look.
local themeInit, themeSections, themeConfig = checkExport("theme document", "builder_theme_export.lua", 1)
if themeInit ~= nil and themeConfig ~= nil then
    assert_eq("Init passes the theme to the config", themeConfig.theme, "storm")
    assert_eq("the borrowed button resolves to neon's ghost variant", themeConfig.resolved.button.variant, "ghost")
    assert_eq("the borrowed button resolves as a pill", themeConfig.resolved.button.pill, true)
    assert_eq("the button keeps its look", themeSections[1].items[1].look, { radius = 0, pill = false })
end

-- The stage 2 document: slate with an xp title bar, a stops list, a bevel, a status bar and a frame
-- written by the builder.
local stage2Init, _, stage2Config = checkExport("stage 2 document", "builder_stage2_export.lua", 1)
if stage2Init ~= nil and stage2Config ~= nil then
    assert_eq("Init passes the slate theme to the config", stage2Config.theme, "slate")
    assert_eq("the exported header resolves to the xpbar variant", stage2Config.resolved.header.variant, "xpbar")
    assert_eq("the exported bar stops resolve as a list of two colours", #stage2Config.resolved.header.barStops, 2)
    assert_eq("the exported progress frame keeps its pad", stage2Config.resolved.progress.frame.pad, 2)
end
-- The library rejects a field the builder would reject, with the same words. This is the other direction:
-- the builder's messages for these cases are in builder/src/schema/validate.test.ts.
local function registerError(item)
    local okState, state = pcall(function()
        local cfg = Config.New()
        cfg.key = 1
        cfg.keyHint = "F6"
        return newState(cfg)
    end)
    if not okState then
        return tostring(state)
    end
    local ok, err = pcall(Registry.Register, state, { id = "Main", items = { item } })
    if ok then
        return nil
    end
    return tostring(err)
end

local function says(err, text)
    return err ~= nil and string.find(err, text, 1, true) ~= nil
end

assert_true("the library rejects a non-boolean enabled", says(registerError({ type = "checkbox", id = "c", label = "C", enabled = "no" }), "enabled must be a boolean"))
assert_true("the library rejects a non-boolean visible", says(registerError({ type = "separator", visible = 1 }), "visible must be a boolean"))
assert_true("the library rejects an unknown label style", says(registerError({ type = "label", label = "L", style = "loud" }), "style must be one of normal, muted, heading, warning"))
assert_true("the library rejects a zero number step", says(registerError({ type = "number", id = "n", label = "N", step = 0 }), "step must be a positive number"))
assert_true("the library rejects an inverted stepper range", says(registerError({ type = "stepper", id = "s", label = "S", min = 5, max = 1 }), "min must be less than max"))
assert_true("the library rejects an inverted progress range", says(registerError({ type = "progress", id = "p", label = "P", min = 5, max = 1 }), "min must be less than max"))
assert_true("the library rejects a multiselect default that is not an option", says(registerError({ type = "multiselect", id = "m", label = "M", options = { "a", "b", "c" }, default = { "z" } }), "default must be one of a, b, c"))
assert_true("the library rejects multiselect columns above four", says(registerError({ type = "multiselect", id = "m", label = "M", options = { "a" }, columns = 5 }), "columns must be a number from 1 to 4"))
assert_true("the library rejects a colorpicker default with a channel above one", says(registerError({ type = "colorpicker", id = "c", label = "C", default = { R = 2, G = 0, B = 0, A = 1 } }), "default.R must be a number from 0 to 1"))
assert_true("the library rejects a colorpicker alpha that is not a boolean", says(registerError({ type = "colorpicker", id = "c", label = "C", alpha = "no" }), "alpha must be a boolean"))
assert_true("the library rejects a zero slider labelWidth", says(registerError({ type = "slider", id = "s", label = "S", min = 0, max = 1, labelWidth = 0 }), "labelWidth must be a positive number"))
