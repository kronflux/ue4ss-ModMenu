-- Specs for the drawn panel effects: the scanline plan, the sparkle spots and the seeded random
-- number generator. The widgets themselves need UE4SS, so only the pure parts are checked here. The
-- shell modules require UEHelpers from the UE4SS install, so an empty stub stands in while they load.
local stubbedUEHelpers = package.loaded["UEHelpers.UEHelpers"] == nil
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = {}
end
local Effects = require("ModMenu.shell.effects")
local Build = require("ModMenu.shell.build")
if stubbedUEHelpers then
    package.loaded["UEHelpers.UEHelpers"] = nil
end

-- A 2.5-unit period over 1200 units is 480 lines.
local plan = Effects.ScanlinePlan(1, 0.38, 2.5, 1200)
assert_eq("1200 units at period 2.5 is 480 lines", #plan, 480)

-- A dark line has alpha strength * (0.55 + 0.9 * r) with r in [0, 1), and a phosphor row has
-- strength * 0.35, so every alpha sits between 0 and strength * 1.45.
local inRange, brights = true, 0
for _, line in ipairs(plan) do
    if line.alpha < 0 or line.alpha > 0.38 * 1.45 then
        inRange = false
    end
    if line.bright then
        brights = brights + 1
        if math.abs(line.alpha - 0.38 * 0.35) > 1e-9 then
            inRange = false
        end
    elseif line.alpha < 0.38 * 0.55 - 1e-9 then
        inRange = false
    end
end
assert_true("every scanline alpha is inside the strength band", inRange)
assert_true("some lines are bright phosphor rows, but not most", brights > 0 and brights < 120)

-- The same seed gives the same plan, and another seed gives a different one.
local again = Effects.ScanlinePlan(1, 0.38, 2.5, 1200)
local same = true
for i = 1, #plan do
    if plan[i].alpha ~= again[i].alpha or plan[i].bright ~= again[i].bright then
        same = false
    end
end
assert_true("the same seed repeats the plan", same)
assert_true("another seed changes the plan", Effects.ScanlinePlan(2, 0.38, 2.5, 1200)[1].alpha ~= plan[1].alpha)

-- The line count follows the period and the height, rounded down.
assert_eq("period 4 over 1200 is 300 lines", #Effects.ScanlinePlan(1, 0.2, 4, 1200), 300)
assert_eq("a zero height has no lines", #Effects.ScanlinePlan(1, 0.2, 2.5, 0), 0)
assert_eq("a zero period has no lines", #Effects.ScanlinePlan(1, 0.2, 0, 1200), 0)

-- Rand steps the seed table and stays in [0, 1).
local g = { seed = 42 }
local a, b = Effects.Rand(g), Effects.Rand(g)
assert_true("Rand stays in the unit interval", a >= 0 and a < 1 and b >= 0 and b < 1 and a ~= b)

-- Six sparkle spots, each with a size of 2 to 4.
local spots = Effects.SparkleSpots()
assert_eq("six sparkle spots", #spots, 6)
assert_eq("sparkle sizes follow StyleLab", { spots[1].size, spots[2].size, spots[3].size, spots[4].size, spots[5].size, spots[6].size },
    { 4, 3, 2, 3, 2, 3 })
assert_true("every spot has a padding of four margins", #spots[1].pad == 4)

-- A flat, square, borderless panel with an effect is not the stock panel, because the stock panel
-- draws no effects. Without one it still is.
local flat = { fill = { R = 0, G = 0, B = 0, A = 1 } }
assert_true("a plain flat panel is stock", Build.IsStockPanel(flat, {}))
assert_true("scanlines make a panel themed", not Build.IsStockPanel({ fill = flat.fill, scanlines = 0.3 }, {}))
assert_true("scanlines true make a panel themed", not Build.IsStockPanel({ fill = flat.fill, scanlines = true }, {}))
assert_true("scanlines 0 leave a panel stock", Build.IsStockPanel({ fill = flat.fill, scanlines = 0 }, {}))
assert_true("a sweep makes a panel themed", not Build.IsStockPanel({ fill = flat.fill, sweep = true }, {}))
assert_true("sparkle motion makes a panel themed", not Build.IsStockPanel(flat, { sparkle = true }))
