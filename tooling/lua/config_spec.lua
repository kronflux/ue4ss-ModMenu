local Config = require("ModMenu.core.config")

local function apply(opts)
    local cfg = Config.New()
    cfg.key = 1
    cfg.keyHint = "F6"
    Config.ApplyInit(cfg, opts)
    return cfg
end

assert_true("showClose default on", Config.New().showClose == true)
assert_true("showClose stays on when omitted", apply({}).showClose == true)
assert_true("showClose false", apply({ showClose = false }).showClose == false)
assert_true("showClose true", apply({ showClose = true }).showClose == true)

local kept = apply({ showClose = false })
Config.ApplyInit(kept, { title = "Keep" })
assert_true("showClose persists across Init", kept.showClose == false)
Config.ApplyInit(kept, { showClose = true })
assert_true("showClose can turn back on", kept.showClose == true)

-- These checks cover the spacing defaults, how host values merge over them, and the errors for bad values, because the shell lays out every gap from these tokens.
assert_eq("spacing default gapSection", Config.New().spacing.gapSection, 18)
local defaults = Config.New().spacing
local expectedSpacing = {
    gapItem = 8,
    gapSection = 18,
    footerPad = 8,
    footerPadTouch = 120,
    confirmWidth = 360,
    tabHeight = 56,
    tabGap = 4,
    tabGapTouch = 8,
    tabPad = 8,
    tabPadTouch = 12,
    dockPad = 8,
    dockPadTouch = 24,
    headPad = 16,
    confirmGap = 8,
    sectionHeaderPadX = 10,
    sectionHeaderPadY = 4,
    sectionHeaderGap = 12,
    tooltipPad = 6,
    tooltipGap = 12,
    tooltipMaxWidth = 320,
}
local expectedOrder = {
    "gapItem", "gapSection", "footerPad", "footerPadTouch", "confirmWidth", "tabHeight",
    "tabGap", "tabGapTouch", "tabPad", "tabPadTouch", "dockPad", "dockPadTouch",
    "headPad", "confirmGap", "sectionHeaderPadX", "sectionHeaderPadY", "sectionHeaderGap",
    "tooltipPad", "tooltipGap", "tooltipMaxWidth",
}
for _, key in ipairs(expectedOrder) do
    assert_eq("spacing default " .. key, defaults[key], expectedSpacing[key])
end
assert_eq("spacing default panelPad is nil", defaults.panelPad, nil)
for key, _ in pairs(defaults) do
    assert_true("spacing default " .. key .. " is expected", expectedSpacing[key] ~= nil)
    local okSet = pcall(Config.NormalizeSpacing, { [key] = 1 })
    assert_true("spacing default " .. key .. " is settable", okSet)
end
local keptSpacing = apply({ spacing = { gapSection = 30, panelPad = 10 } })
Config.ApplyInit(keptSpacing, { title = "No spacing" })
assert_eq("spacing Init without spacing keeps gapSection", keptSpacing.spacing.gapSection, 30)
assert_eq("spacing Init without spacing keeps panelPad", keptSpacing.spacing.panelPad, 10)
assert_eq("spacing override gapSection", Config.NormalizeSpacing({ gapSection = 24 }).gapSection, 24)
assert_eq("spacing override keeps gapItem", Config.NormalizeSpacing({ gapSection = 24 }).gapItem, 8)
assert_eq("spacing nil gives defaults", Config.NormalizeSpacing(nil).gapItem, 8)
assert_eq("spacing panelPad is a number", Config.NormalizeSpacing({ panelPad = 10 }).panelPad, 10)
assert_eq("spacing zero is valid", Config.NormalizeSpacing({ gapItem = 0 }).gapItem, 0)
local okNeg, errNeg = pcall(Config.NormalizeSpacing, { gapItem = -1 })
assert_true("spacing negative errors", okNeg == false)
assert_true("spacing negative error names key and rule",
    string.find(tostring(errNeg), "spacing.gapItem must be a number of zero or more", 1, true) ~= nil)
local okHuge, errHuge = pcall(Config.NormalizeSpacing, { tabGap = math.huge })
assert_true("spacing math.huge errors", okHuge == false)
assert_true("spacing math.huge error names key and rule",
    string.find(tostring(errHuge), "spacing.tabGap must be a number of zero or more", 1, true) ~= nil)
local merged = apply({ spacing = { gapSection = 24 } })
Config.ApplyInit(merged, { spacing = { tabGap = 20 } })
assert_eq("spacing second Init keeps earlier override", merged.spacing.gapSection, 24)
assert_eq("spacing second Init applies its key", merged.spacing.tabGap, 20)
assert_eq("spacing second Init keeps other defaults", merged.spacing.gapItem, 8)
assert_true("spacing New tables are not shared", Config.New().spacing ~= Config.New().spacing)
local okBad, errBad = pcall(Config.NormalizeSpacing, { gapItem = "x" })
assert_true("spacing non-number errors", okBad == false)
assert_true("spacing error names gapItem", string.find(tostring(errBad), "gapItem", 1, true) ~= nil)
local okTypo, errTypo = pcall(Config.NormalizeSpacing, { gapItme = 4 })
assert_true("spacing unknown key errors", okTypo == false)
assert_true("spacing unknown key error names key", string.find(tostring(errTypo), "gapItme", 1, true) ~= nil)
local okTable = pcall(Config.NormalizeSpacing, 5)
assert_true("spacing non-table errors", okTable == false)
assert_eq("spacing via Init", apply({ spacing = { tabGap = 20 } }).spacing.tabGap, 20)

-- The tooltip delay is a config token beside spacing, because it is a time rather than a distance.
assert_eq("tooltipDelayMs default", Config.New().tooltipDelayMs, 400)
assert_eq("tooltipDelayMs via Init", apply({ tooltipDelayMs = 250 }).tooltipDelayMs, 250)
local keptDelay = apply({ tooltipDelayMs = 250 })
Config.ApplyInit(keptDelay, { title = "Keep delay" })
assert_eq("tooltipDelayMs persists across Init", keptDelay.tooltipDelayMs, 250)
local okDelay, errDelay = pcall(apply, { tooltipDelayMs = -1 })
assert_true("tooltipDelayMs negative errors", okDelay == false)
assert_true("tooltipDelayMs error names the rule",
    string.find(tostring(errDelay), "tooltipDelayMs must be a number of zero or more", 1, true) ~= nil)

-- These checks cover Init's theme, style and fonts options, because every shell part and widget draws from config.resolved.
local Theme = require("ModMenu.core.theme")
local function has(err, text)
    return string.find(tostring(err), text, 1, true) ~= nil
end

local slate = apply({ theme = "slate" })
assert_eq("theme slate sets config.theme", slate.theme, "slate")
assert_eq("theme slate resolves the panel radius", slate.resolved.panel.radius, 14)
assert_eq("theme slate leaves themeDef nil", slate.themeDef, nil)

Config.ApplyInit(slate, { style = { button = "light" } })
assert_eq("style borrows the light button shape on slate", slate.resolved.button.radius, 0)
Config.ApplyInit(slate, { style = { toggle = { w = 40 } } })
assert_eq("a later style keeps the earlier button borrow", slate.style.button, "light")
assert_eq("a later style keeps the borrowed button radius", slate.resolved.button.radius, 0)
assert_eq("a later style applies its toggle width", slate.resolved.toggle.w, 40)
Config.ApplyInit(slate, { style = { toggle = { h = 24 } } })
assert_eq("a later table merges over the earlier toggle table", slate.style.toggle, { w = 40, h = 24 })
Config.ApplyInit(slate, { style = { button = { height = 40 } } })
assert_eq("a table over a borrowed type keeps the borrow as from", slate.style.button, { from = "light", height = 40 })
assert_eq("a table over a borrowed type keeps the borrowed radius", slate.resolved.button.radius, 0)

local beforeTheme = apply({ theme = "dark" })
local okNope, errNope = pcall(Config.ApplyInit, beforeTheme, { theme = "nope" })
assert_true("theme nope errors", okNope == false)
assert_true("theme nope error lists the ids", has(errNope, "light, dark, slate"))
assert_eq("theme nope leaves config.theme", beforeTheme.theme, "dark")

local beforeStyle = apply({ style = { toggle = { w = 30 } } })
local styleBefore = beforeStyle.style
local resolvedBefore = beforeStyle.resolved
local colorsBefore = beforeStyle.colors
local okWobble, errWobble = pcall(Config.ApplyInit, beforeStyle, { theme = "slate", style = { wobble = {} } })
assert_true("style wobble errors", okWobble == false)
assert_true("style wobble error names the type", has(errWobble, "unknown object type wobble"))
assert_true("style wobble error names Init", has(errWobble, "ModMenu.Init: style"))
assert_true("style wobble leaves config.style", beforeStyle.style == styleBefore)
assert_eq("style wobble leaves the toggle override", beforeStyle.style.toggle, { w = 30 })
assert_eq("style wobble leaves config.theme although theme was valid", beforeStyle.theme, "light")
assert_true("style wobble leaves config.resolved", beforeStyle.resolved == resolvedBefore)
assert_true("style wobble leaves config.colors", beforeStyle.colors == colorsBefore)

local okField, errField = pcall(apply, { style = { button = { wobble = 1 } } })
assert_true("style unknown field errors", okField == false)
assert_true("style unknown field error names the field", has(errField, "button.wobble is not a known field"))

local beforeFonts = apply({ fonts = { title = "/Game/Fonts/A.A" } })
local okFont, errFont = pcall(Config.ApplyInit, beforeFonts, { fonts = { kanit = 5 } })
assert_true("fonts with a number errors", okFont == false)
assert_true("fonts error names fonts.kanit", has(errFont, "fonts.kanit"))
assert_eq("fonts error leaves config.fonts", beforeFonts.fonts, { title = "/Game/Fonts/A.A" })
Config.ApplyInit(beforeFonts, { fonts = { kanit = "/Game/Fonts/Kanit.Kanit" } })
assert_eq("a later fonts table merges over the earlier one", beforeFonts.fonts,
    { title = "/Game/Fonts/A.A", kanit = "/Game/Fonts/Kanit.Kanit" })

local okLate, errLate = pcall(Config.ApplyInit, beforeTheme, { theme = "slate", tooltipDelayMs = -1 })
assert_true("a later option error fails Init", okLate == false and has(errLate, "tooltipDelayMs"))
assert_eq("a later option error leaves config.theme", beforeTheme.theme, "dark")

-- light and dark keep today's legacy colours exactly, so code that reads config.colors draws as before.
assert_eq("theme light keeps config.colors equal to Theme.Resolve", apply({ theme = "light" }).colors, Theme.Resolve("light"))
assert_eq("theme dark keeps config.colors equal to Theme.Resolve", apply({ theme = "dark" }).colors, Theme.Resolve("dark"))
assert_eq("New keeps config.colors equal to the light preset", Config.New().colors, Theme.Preset("light"))
local red = { R = 1, G = 0, B = 0, A = 1 }
assert_eq("theme dark with colors matches Theme.Resolve with them",
    apply({ theme = "dark", colors = { panelBg = red } }).colors, Theme.Resolve("dark", { panelBg = red }))
local mergedColors = apply({ theme = "dark", colors = { panelBg = red } })
Config.ApplyInit(mergedColors, { colors = { buttonBg = red } })
assert_eq("colors alone keeps the earlier override", mergedColors.colors.panelBg, red)
assert_eq("colors alone applies its own token", mergedColors.colors.buttonBg, red)
assert_eq("colors alone reaches the resolved style", mergedColors.resolved.button.roles.default.fill, red)
Config.ApplyInit(mergedColors, { theme = "dark" })
assert_eq("a new theme drops earlier colour overrides", mergedColors.colors, Theme.Resolve("dark"))
local okColors = pcall(apply, { colors = 5 })
assert_true("colors that is not a table errors", okColors == false)
local okThemeColors, themeColors = pcall(apply, { theme = "dark", colors = "x" })
assert_true("theme with colors that is not a table is accepted as before", okThemeColors)
if okThemeColors then
    assert_eq("theme with colors that is not a table ignores the colors", themeColors.colors, Theme.Resolve("dark"))
end

local titled = apply({ title = "Before" })
local okTitled = pcall(Config.ApplyInit, titled, { title = "After", dock = "left", style = { wobble = {} } })
assert_true("a bad style fails Init", okTitled == false)
assert_eq("a bad style leaves config.title", titled.title, "Before")
assert_eq("a bad style leaves config.dock", titled.dock, "right")

local okNopePart, errNopePart = pcall(apply, { style = { button = "nope" } })
assert_true("a style borrow of an unknown preset errors", okNopePart == false)
assert_true("a style borrow error carries the Init prefix", has(errNopePart, "ModMenu.Init: style: button: unknown theme \"nope\""))
assert_true("a style borrow error lists the ids", has(errNopePart, "light, dark, slate"))

local custom = apply({ theme = { base = "slate", panel = { radius = 20 } } })
assert_eq("a definition table sets config.theme to custom", custom.theme, "custom")
assert_eq("a definition table is kept in themeDef", custom.themeDef.panel.radius, 20)
assert_eq("a definition table resolves its own fields", custom.resolved.panel.radius, 20)
local okDef, errDef = pcall(apply, { theme = { panel = { wobble = 1 } } })
assert_true("a definition table with an unknown field errors", okDef == false and has(errDef, "panel.wobble"))
assert_true("a definition error has one prefix directly before the inner message",
    has(errDef, "ModMenu.Init: theme: panel.wobble is not a known field"))

-- StyleKey decides whether a later Init rebuilds the shell, so it must move with the look and only with the look.
local stubbedHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local okLife, Lifecycle = pcall(require, "ModMenu.shell.lifecycle")
local okReg, Registry = pcall(require, "ModMenu.shell.registry")
if stubbedHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end
assert_true("shell.lifecycle loads under MoonSharp", okLife)
assert_true("shell.registry loads under MoonSharp", okReg)
if okLife then
    local keyed = apply({ theme = "light" })
    local key1 = Lifecycle.StyleKey(keyed)
    Config.ApplyInit(keyed, { title = "Only the title" })
    assert_eq("StyleKey is equal after a title-only Init", Lifecycle.StyleKey(keyed), key1)
    Config.ApplyInit(keyed, { theme = "slate" })
    local key2 = Lifecycle.StyleKey(keyed)
    assert_true("StyleKey differs after a theme change", key2 ~= key1)
    Config.ApplyInit(keyed, { style = { toggle = { w = 40 } } })
    local key3 = Lifecycle.StyleKey(keyed)
    assert_true("StyleKey differs after a style change", key3 ~= key2)
    Config.ApplyInit(keyed, { fonts = { kanit = "/Game/Fonts/Kanit.Kanit" } })
    local key4 = Lifecycle.StyleKey(keyed)
    assert_true("StyleKey differs after a fonts change", key4 ~= key3)
    Config.ApplyInit(keyed, { colors = { panelBg = red } })
    assert_true("StyleKey differs after a colors change", Lifecycle.StyleKey(keyed) ~= key4)

    -- A changed look rebuilds only when a shell exists and was built with another key.
    assert_true("the first Init does not rebuild", Lifecycle.NeedsRebuild(nil, "a", true) == false)
    assert_true("an unchanged key does not rebuild", Lifecycle.NeedsRebuild("a", "a", true) == false)
    assert_true("a changed key with no shell does not rebuild", Lifecycle.NeedsRebuild("a", "b", false) == false)
    assert_true("a changed key with a shell rebuilds", Lifecycle.NeedsRebuild("a", "b", true) == true)

    -- The rebuild waits for a later tick, several Inits in one tick schedule it once, and the built
    -- key moves only when it runs. The run is checked with the shell gone, because building widgets
    -- needs UMG.
    local savedDelay = ExecuteInGameThreadWithDelay
    local scheduled = {}
    ExecuteInGameThreadWithDelay = function(ms, fn)
        scheduled[#scheduled + 1] = { ms = ms, fn = fn }
    end
    local live = apply({ theme = "light" })
    local builtKey = Lifecycle.StyleKey(live)
    local shell = { config = live, styleKey = builtKey, menuRoot = { IsValid = function() return true end } }
    Config.ApplyInit(live, { theme = "slate" })
    Lifecycle.OnConfigChanged(shell)
    Config.ApplyInit(live, { theme = "neon" })
    Lifecycle.OnConfigChanged(shell)
    assert_eq("two look changes in one tick schedule one rebuild", #scheduled, 1)
    assert_true("the rebuild waits a positive delay", scheduled[1] ~= nil and scheduled[1].ms > 0)
    assert_eq("the built key stays until the rebuild runs", shell.styleKey, builtKey)
    shell.menuRoot = nil
    if scheduled[1] ~= nil then
        scheduled[1].fn()
    end
    assert_eq("the rebuild stores the latest key when it runs", shell.styleKey, Lifecycle.StyleKey(live))
    assert_true("the rebuild clears its pending mark", shell.rebuildPending ~= true)

    -- Register caches its content rebuild in S.rebuildFn, so the style rebuild must not take that
    -- function or that field.
    scheduled = {}
    local contentRuns = 0
    local contentFn = function()
        contentRuns = contentRuns + 1
    end
    local mixed = apply({ theme = "light" })
    local mixedShell = { config = mixed, styleKey = Lifecycle.StyleKey(mixed), rebuildFn = contentFn,
        menuRoot = { IsValid = function() return true end } }
    Config.ApplyInit(mixed, { theme = "slate" })
    Lifecycle.OnConfigChanged(mixedShell)
    assert_eq("a look change after Register schedules one call", #scheduled, 1)
    assert_true("the scheduled call is the style rebuild, not the content rebuild",
        scheduled[1] ~= nil and scheduled[1].fn ~= contentFn)
    assert_true("the content rebuild keeps its own field", mixedShell.rebuildFn == contentFn)
    mixedShell.menuRoot = nil
    if scheduled[1] ~= nil then
        scheduled[1].fn()
    end
    assert_eq("the style rebuild does not run the content rebuild", contentRuns, 0)
    assert_true("the style rebuild clears its pending mark after Register", mixedShell.rebuildPending ~= true)
    assert_eq("the style rebuild stores the key after Register", mixedShell.styleKey, Lifecycle.StyleKey(mixed))
    ExecuteInGameThreadWithDelay = savedDelay
end

-- An item's look is checked against its widget's object type when the section is registered.
if okReg then
    local function registerItem(item)
        local cfg = Config.New()
        cfg.key = 1
        cfg.keyHint = "F6"
        local state = {
            config = cfg, values = {}, liveControls = {}, itemNodes = {}, sections = {}, sectionIndexById = {},
            collapsedById = {}, foldCollapsedByKey = {}, menuOpen = false,
            makeWidgetCtx = function()
                return {}
            end,
        }
        return pcall(Registry.Register, state, { id = "Main", items = { item } })
    end
    local okLook, errLook = registerItem({ type = "button", id = "go", label = "Go", look = { radius = 0 } })
    assert_true("a button look with radius registers", okLook)
    if not okLook then
        assert_eq("a button look with radius error", tostring(errLook), "")
    end
    local okBadLook, errBadLook = registerItem({ type = "button", id = "go", label = "Go", look = { wobble = 1 } })
    assert_true("a button look with wobble errors", okBadLook == false)
    assert_true("a button look error names the item", has(errBadLook, "Register(Main) items[1].look"))
    assert_true("a button look error names the field", has(errBadLook, "button.wobble"))
    local okToggle = registerItem({ type = "checkbox", id = "on", label = "On", look = { w = 40 } })
    assert_true("a checkbox look with a toggle field registers", okToggle)
    local okRoles, errRoles = registerItem({ type = "checkbox", id = "on", label = "On", look = { roles = {} } })
    assert_true("a checkbox look is checked as toggle", okRoles == false and has(errRoles, "toggle.roles"))
    local okSep, errSep = registerItem({ type = "separator", look = { radius = 0 } })
    assert_true("a separator rejects look", okSep == false and has(errSep, "look is not supported"))
    local okRow, errRow = registerItem({ type = "row", items = {
        { type = "button", id = "a", label = "A", look = { wobble = 1 } },
    } })
    assert_true("a look inside a row is checked", okRow == false and has(errRow, "items[1].items[1].look"))
    -- An item look cannot borrow from a preset, so a `from` there is reported rather than ignored.
    local okFrom, errFrom = registerItem({ type = "button", id = "go", label = "Go", look = { from = "neon" } })
    assert_true("a button look with from errors", okFrom == false)
    assert_true("a button look from error names the field",
        has(errFrom, "Register(Main) items[1].look: button.from is not a known field"))
end
