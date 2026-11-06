-- Specs for the motion maths and the tick: the open stagger, shake, pop, the glitch generator, and
-- the rule that a menu with every motion off makes no widget calls. Widgets are recording fakes,
-- because UMG needs UE4SS.
local Motion = require("ModMenu.core.motion")

-- The spec host has no os.clock, so a fixed fake clock stands in and is restored at the end.
local realClock = Motion._clock
Motion._clock = function()
    return 100
end

local function near(a, b)
    return math.abs(a - b) < 1e-9
end

-- The open stagger: index 1 starts at once, index 2 one step later, and both end at rest.
local o, y = Motion.OpenState(0, 1)
assert_true("OpenState starts transparent and 24 units low", o == 0 and y == 24)
o, y = Motion.OpenState(0.32, 1)
assert_true("OpenState ends at opacity 1 and offset 0", o == 1 and y == 0)
o, y = Motion.OpenState(0.06, 2)
assert_true("the second index waits one stagger step", o == 0 and y == 24)
o, y = Motion.OpenState(0.06 + 0.16, 2)
assert_true("halfway through the duration the cubic ease is at 0.875", near(o, 0.875) and near(y, 3))
assert_true("long after the end the state is exactly at rest", select(1, Motion.OpenState(99, 5)) == 1)

-- Shake and pop.
assert_eq("ShakeX is zero when the shake ends", Motion.ShakeX(0.4), 0)
assert_eq("ShakeX is zero after the shake ends", Motion.ShakeX(1), 0)
assert_true("ShakeX swings early", math.abs(Motion.ShakeX(0.02)) > 0)
assert_true("PopScale peaks at 1.015", near(Motion.PopScale(0.125), 1.015))
assert_eq("PopScale is 1 when the pop ends", Motion.PopScale(0.25), 1)

-- The glitch generator: with a fixed seed, 200 steps of 16 ms give a glitch, and each has an effect.
local g = Motion.NewGlitch(777)
local glitches, bare = 0, 0
for i = 1, 200 do
    local fx = Motion.StepGlitch(g, i * 0.016)
    if fx.glitching then
        glitches = glitches + 1
        if not (fx.jitter or fx.split or fx.flicker or fx.tear or fx.roll) then
            bare = bare + 1
        end
    end
end
assert_true("a seeded glitch generator glitches within 3.2 seconds", glitches > 0)
assert_eq("every glitch has at least one effect", bare, 0)

-- The same seed repeats, and two seeds start at different times.
local function FirstGlitch(seed)
    local gen = Motion.NewGlitch(seed)
    for i = 1, 1000 do
        if Motion.StepGlitch(gen, i * 0.016).glitching then
            return i
        end
    end
    return nil
end
assert_eq("the same seed gives the same first glitch", FirstGlitch(5), FirstGlitch(5))
assert_true("two seeds give different first glitch times", FirstGlitch(5) ~= FirstGlitch(6))

-- Recording widgets, for the tick.
local function Fake()
    local w = { calls = 0 }
    w.SetRenderOpacity = function(self, v)
        self.calls = self.calls + 1
        self.opacity = v
    end
    w.SetRenderTranslation = function(self, v)
        self.calls = self.calls + 1
        self.x, self.y = v.X, v.Y
    end
    w.SetRenderScale = function(self, v)
        self.calls = self.calls + 1
        self.scale = v.X
    end
    w.SetVisibility = function(self, v)
        self.calls = self.calls + 1
        self.vis = v
    end
    return w
end

local function Session(motion, panel)
    local root = Fake()
    local s1, s2 = Fake(), Fake()
    return {
        config = { resolved = { motion = motion, panel = panel or {} } },
        panelRoot = root,
        fx = { root = root, sparkles = {}, ghosts = {}, sections = { { s1 }, { s2 } } },
    }, root, s1, s2
end

-- Every motion off: no widget call on any tick, even straight after Start.
local S, root, s1 = Session({})
Motion.Start(S, 10)
for i = 1, 20 do
    Motion.Tick(S, 10 + i * 0.016)
end
assert_eq("a menu with every motion off makes no widget calls", root.calls + s1.calls, 0)

-- Open on: the root and sections start low and transparent, and end at exactly rest.
S, root, s1 = Session({ open = true })
local s2 = S.fx.sections[2][1]
Motion.Start(S, 10)
assert_true("Start writes the first frame at once", root.opacity == 0 and root.y == 24 and s1.opacity == 0)
Motion.Tick(S, 10.1)
assert_true("mid-stagger the root has risen", root.opacity > 0 and root.opacity < 1)
Motion.Tick(S, 10 + 0.06 * 2 + 0.32 + 0.01)
assert_true("after the stagger the root rests", root.opacity == 1 and root.y == 0 and root.scale == 1 and root.x == 0)
assert_true("after the stagger the sections rest", s1.opacity == 1 and s1.y == 0 and s2.opacity == 1 and s2.y == 0)
local before = root.calls + s1.calls + s2.calls
for i = 1, 10 do
    Motion.Tick(S, 11 + i * 0.016)
end
assert_eq("a settled menu stops writing", root.calls + s1.calls + s2.calls, before)

-- Open off: the sections are never written, even with a start time.
S, root, s1 = Session({ open = false, pop = true })
Motion.Start(S, 10)
Motion.Tick(S, 10.05)
assert_eq("open off writes nothing to the root or the sections", root.calls + s1.calls, 0)

-- Pop: a start time scales only the root, then settles to scale exactly 1.
Motion.Pop(S)
assert_true("Pop records a start time", S.popAt ~= nil)
Motion.Tick(S, S.popAt + 0.125)
assert_true("mid-pop the root is scaled up", near(root.scale, 1.015))
Motion.Tick(S, S.popAt + 0.3)
assert_true("after the pop the scale is exactly 1", root.scale == 1 and S.popAt == nil)
assert_eq("pop never writes a section", s1.calls, 0)

-- Pop and shake do nothing when their field is off.
S = Session({})
Motion.Pop(S)
Motion.Shake(S)
assert_true("Pop and Shake record nothing when off", S.popAt == nil and S.shakeAt == nil)

-- Shake settles to x exactly 0.
S, root = Session({ shake = true })
Motion.Shake(S)
Motion.Tick(S, S.shakeAt + 0.02)
assert_true("mid-shake the root is displaced", root.x ~= 0)
Motion.Tick(S, S.shakeAt + 0.5)
assert_true("after the shake the root is back at x 0", root.x == 0 and S.shakeAt == nil)

-- Pulse, cursor and sparkles only touch their own widgets.
S = Session({ pulse = true, cursor = true, sparkle = true })
local title, cursor, dot = Fake(), Fake(), Fake()
S.fx.title, S.fx.cursor, S.fx.sparkles = title, cursor, { dot }
Motion.Tick(S, 0.25)
assert_true("pulse keeps the title between 0.6 and 1", title.opacity >= 0.6 and title.opacity <= 1)
assert_true("the cursor is shown in the first half second", cursor.vis == 3)
Motion.Tick(S, 0.75)
assert_true("the cursor is hidden in the second half", cursor.vis == 2)
assert_true("a sparkle is at least 0.15 bright", dot.opacity >= 0.15 and dot.opacity <= 1)
assert_eq("none of them moves the root", S.panelRoot.calls, 0)

-- The sweep and noise bands travel only with panel.sweep.
S = Session({}, { sweep = true })
local sweep, noise = Fake(), Fake()
S.fx.sweep, S.fx.noise = sweep, noise
Motion.Tick(S, 1)
Motion.Tick(S, 1.1)
assert_true("the sweep and noise bands move", sweep.y ~= nil and noise.y ~= nil)
S = Session({}, {})
S.fx.sweep = Fake()
Motion.Tick(S, 1)
assert_eq("without panel.sweep the band stays", S.fx.sweep.calls, 0)

-- Stop clears the start times and puts a half-finished menu back at rest.
S, root = Session({ open = true })
Motion.Start(S, 10)
Motion.Stop(S)
assert_true("Stop clears the times", S.openedAt == nil and S.popAt == nil and S.shakeAt == nil)
assert_true("Stop leaves the root at rest", root.opacity == 1 and root.y == 0)

Motion._clock = realClock
