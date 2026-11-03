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
}
local expectedOrder = {
    "gapItem", "gapSection", "footerPad", "footerPadTouch", "confirmWidth", "tabHeight",
    "tabGap", "tabGapTouch", "tabPad", "tabPadTouch", "dockPad", "dockPadTouch",
    "headPad", "confirmGap", "sectionHeaderPadX", "sectionHeaderPadY", "sectionHeaderGap",
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
