/**
 * Tests for tools/gen-themes.mjs.
 *
 * Run: node --test tools/gen-themes.test.mjs
 *
 * Each test that changes a file works on a copy of themes/ in a temporary folder, so the
 * repository is never written.
 */

import { test, after } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { spawnSync } from "node:child_process";

import { OUTPUTS, check, generate, isEntry, parseArgs, write } from "./gen-themes.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..");

const temps = [];

/** Copy themes/ into a new temporary folder and return the folder. */
function tempRoot() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gen-themes-"));
  temps.push(dir);
  fs.cpSync(path.join(ROOT, "themes"), path.join(dir, "themes"), { recursive: true });
  return dir;
}

after(() => {
  for (const dir of temps) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("generating the repository returns the four output paths", () => {
  const files = generate(ROOT);
  assert.deepEqual([...files.keys()].sort(), [
    "builder/src/theme/fields.generated.ts",
    "builder/src/theme/presets.generated.ts",
    "core/presets.lua",
    "core/stylefields.lua",
  ]);
  assert.deepEqual([...files.keys()].sort(), [...OUTPUTS].sort());
  for (const text of files.values()) {
    assert.match(text.split("\n")[0], /generated.*node tools\/gen-themes\.mjs/i);
  }
});

test("check returns no stale path right after writing", () => {
  const dir = tempRoot();
  write(dir);
  assert.deepEqual(check(dir), []);
});

test("changing one colour in slate.json makes both preset outputs stale", () => {
  const dir = tempRoot();
  write(dir);
  const file = path.join(dir, "themes", "presets", "slate.json");
  const slate = JSON.parse(fs.readFileSync(file, "utf8"));
  slate.palette.accent = "#22F1FF";
  fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
  assert.deepEqual(check(dir).sort(), ["builder/src/theme/presets.generated.ts", "core/presets.lua"]);
});

test("an unknown argument stops the script with exit 2 and the usage", () => {
  assert.deepEqual(parseArgs([]), { check: false });
  assert.deepEqual(parseArgs(["--check"]), { check: true });
  assert.ok("error" in parseArgs(["--chek"]));
  const run = spawnSync(process.execPath, [path.join(__dirname, "gen-themes.mjs"), "--chek"], { encoding: "utf8" });
  assert.equal(run.status, 2);
  assert.match(run.stderr, /unknown argument "--chek"/);
  assert.match(run.stderr, /Usage: node tools\/gen-themes\.mjs \[--check\]/);
  assert.doesNotMatch(run.stdout, /wrote /);
});

test("the entry guard matches the script through a directory link", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gen-themes-link-"));
  const link = path.join(dir, "tools-link");
  // A junction needs no administrator rights on Windows; elsewhere a directory symlink is used.
  fs.symlinkSync(__dirname, link, process.platform === "win32" ? "junction" : "dir");
  try {
    const self = path.join(__dirname, "gen-themes.mjs");
    assert.equal(isEntry(path.join(link, "gen-themes.mjs"), self), true);
    assert.equal(isEntry(path.join(link, "gen-themes.test.mjs"), self), false);
    assert.equal(isEntry(undefined, self), false);
  } finally {
    // Remove the link itself first, so no recursive delete can ever walk into tools/ through it.
    if (process.platform === "win32") fs.rmdirSync(link);
    else fs.unlinkSync(link);
    fs.rmdirSync(dir);
  }
});

test("bad elements in progress.ramp and panel.shadowLayers fail with the file and field named", () => {
  const cases = [
    [(s) => (s.progress = { ramp: ["#2FB34A", null] }), "progress.ramp[2]"],
    [(s) => (s.progress = { ramp: ["#2FB34A", "#12"] }), "progress.ramp[2]"],
    [(s) => (s.panel = { ...s.panel, shadowLayers: [[0.3]] }), "panel.shadowLayers[1]"],
    [(s) => (s.panel = { ...s.panel, bevel: { light: null } }), "panel.bevel.light"],
  ];
  for (const [change, field] of cases) {
    const dir = tempRoot();
    const file = path.join(dir, "themes", "presets", "slate.json");
    const slate = JSON.parse(fs.readFileSync(file, "utf8"));
    change(slate);
    fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
    assert.throws(
      () => generate(dir),
      (err) => err instanceof Error && err.message.includes("slate.json") && err.message.includes(field),
      `expected an error naming slate.json and ${field}`,
    );
  }
});

test("a stage 2 kind rejects a bad entry with the file and field named", () => {
  const cases = [
    [(s) => (s.header = { barStops: ["#zz", "#000000"] }), "header.barStops[1]"],
    [(s) => (s.header = { barStops: ["#000000"] }), "header.barStops"],
    [(s) => (s.panel = { ...s.panel, bevel: { light: "#12", dark: "#000000" } }), "panel.bevel.light"],
    [(s) => (s.panel = { ...s.panel, bevel: { glow: "#000000" } }), "panel.bevel.glow"],
    [(s) => (s.panel = { ...s.panel, statusBar: { text: 5, fill: "#000000", line: "#000000" } }), "panel.statusBar.text"],
    [(s) => (s.button = { ...s.button, faces: { wobble: {} } }), "button.faces.wobble"],
    [(s) => (s.button = { ...s.button, faces: { primary: { fill: "#12" } } }), "button.faces.primary.fill"],
    [(s) => (s.button = { ...s.button, xp: { face: ["#000000"] } }), "button.xp.face"],
    [(s) => (s.progress = { frame: { pad: "x" } }), "progress.frame.pad"],
    [(s) => (s.panel = { ...s.panel, bevel: ["#000000"] }), "panel.bevel"],
    [(s) => (s.button = { ...s.button, faces: { primary: ["x"] } }), "button.faces.primary"],
    [(s) => (s.progress = { frame: { bevel: { light: "#12" } } }), "progress.frame.bevel.light"],
  ];
  for (const [change, field] of cases) {
    const dir = tempRoot();
    const file = path.join(dir, "themes", "presets", "slate.json");
    const slate = JSON.parse(fs.readFileSync(file, "utf8"));
    change(slate);
    fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
    assert.throws(
      () => generate(dir),
      (err) => err instanceof Error && err.message.includes("slate.json") && err.message.includes(field),
      `expected an error naming slate.json and ${field}`,
    );
  }
});

test("a stage 2 kind accepts a valid value and writes it to both outputs", () => {
  const dir = tempRoot();
  const file = path.join(dir, "themes", "presets", "slate.json");
  const slate = JSON.parse(fs.readFileSync(file, "utf8"));
  slate.header = { variant: "xpbar", barStops: ["#000080", "#1084D0"], captions: "close", controlFace: "#C0C0C0" };
  slate.button = {
    ...slate.button,
    variant: "classic",
    faces: { primary: { fill: "#C0C0C0", text: "#000000" } },
    bevel: { light: "#DFDFDF", dark: "#0A0A0A", width: 2 },
    xp: { edge: "#003C74", glow: "#F8B33A", face: ["#FFFFFF", "#F4F3EE"], pressedFace: ["#F4F3EE", "#C0C0C0"] },
  };
  slate.motion = { open: false, pop: false, shake: false };
  fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
  const files = generate(dir);
  assert.match(files.get("core/presets.lua"), /barStops = \{ "#000080", "#1084D0" \}/);
  assert.match(files.get("builder/src/theme/presets.generated.ts"), /barStops: \[ "#000080", "#1084D0" \]/);
});

test("an empty list is accepted for a fixed-key kind, as an empty table", () => {
  const dir = tempRoot();
  const file = path.join(dir, "themes", "presets", "slate.json");
  const slate = JSON.parse(fs.readFileSync(file, "utf8"));
  slate.panel = { ...slate.panel, bevel: [] };
  slate.button = { ...slate.button, faces: [] };
  fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
  assert.doesNotThrow(() => generate(dir));
});

test("the field list declares each stage 2 kind", () => {
  const fields = JSON.parse(fs.readFileSync(path.join(ROOT, "themes", "fields.json"), "utf8"));
  assert.equal(fields.types.panel.bevel, "bevel");
  assert.equal(fields.types.panel.statusBar, "statusbar");
  assert.equal(fields.types.header.barStops, "stops");
  assert.equal(fields.types.button.faces, "faces");
  assert.equal(fields.types.button.xp, "xpface");
  assert.equal(fields.types.progress.frame, "frame");
  assert.equal(fields.types.progress.block, "stops");
  assert.equal(fields.types.progress.ramp, "table");
});

test("an unknown field fails with the file and the field named", () => {
  const dir = tempRoot();
  const file = path.join(dir, "themes", "presets", "slate.json");
  const slate = JSON.parse(fs.readFileSync(file, "utf8"));
  slate.button = { ...(slate.button || {}), wobble: 1 };
  fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
  assert.throws(
    () => generate(dir),
    (err) => err instanceof Error && err.message.includes("slate.json") && err.message.includes("button.wobble"),
  );
});

test("the field list declares the arrow button kind, the scroll type and the XP control fields", () => {
  const fields = JSON.parse(fs.readFileSync(path.join(ROOT, "themes", "fields.json"), "utf8"));
  const t = fields.types;
  assert.equal(t.field.arrow, "arrowbutton");
  assert.equal(t.stepper.arrows, "boolean");
  assert.match(t.tabs.variant, /\|xp(\||$)/);
  assert.match(t.slider.variant, /\|pointer(\||$)/);
  assert.equal(t.tabs.faceStops, "stops");
  assert.equal(t.tabs.markLineStops, "stops");
  assert.equal(t.tabs.markLine, "color");
  assert.equal(t.toggle.checkFace, "stops");
  assert.equal(t.toggle.checkHoverRing, "color");
  assert.equal(t.choice.radioRings, "stops");
  assert.equal(t.choice.radioHoverRing, "color");
  assert.equal(t.choice.radioBevel, "bevel");
  assert.equal(t.slider.thumbRadius, "number");
  assert.equal(t.slider.ticks, "number");
  assert.equal(t.slider.tickColor, "color");
  assert.equal(t.slider.trackLight, "color");
  assert.deepEqual(t.scroll, {
    track: "color",
    thumb: "color",
    thumbHover: "color",
    thumbEdge: "color",
    thumbRadius: "radius",
    width: "number",
  });
});

test("an arrow button or scroll entry with a bad value fails with the file and field named", () => {
  const cases = [
    [(s) => (s.field = { arrow: { face: ["#FFFFFF"] } }), "field.arrow.face"],
    [(s) => (s.field = { arrow: { wobble: 1 } }), "field.arrow.wobble"],
    [(s) => (s.field = { arrow: { glyph: "#12" } }), "field.arrow.glyph"],
    [(s) => (s.field = { arrow: { size: "big" } }), "field.arrow.size"],
    [(s) => (s.field = { arrow: { bevel: { light: "#12" } } }), "field.arrow.bevel.light"],
    [(s) => (s.field = { arrow: ["#000000"] }), "field.arrow"],
    [(s) => (s.scroll = { thumb: 3 }), "scroll.thumb"],
    [(s) => (s.scroll = { wobble: 1 }), "scroll.wobble"],
    [(s) => (s.slider = { variant: "triangle" }), "slider.variant"],
    [(s) => (s.tabs = { variant: "xpish" }), "tabs.variant"],
  ];
  for (const [change, field] of cases) {
    const dir = tempRoot();
    const file = path.join(dir, "themes", "presets", "slate.json");
    const slate = JSON.parse(fs.readFileSync(file, "utf8"));
    change(slate);
    fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
    assert.throws(
      () => generate(dir),
      (err) => err instanceof Error && err.message.includes("slate.json") && err.message.includes(field),
      `expected an error naming slate.json and ${field}`,
    );
  }
});

test("an arrow button, scroll and XP control entry is accepted and written to both outputs", () => {
  const dir = tempRoot();
  const file = path.join(dir, "themes", "presets", "slate.json");
  const slate = JSON.parse(fs.readFileSync(file, "utf8"));
  slate.field = {
    arrow: {
      face: ["#FFFFFF", "#ECE9D8"],
      hoverFace: ["#FFFFFF", "#FFF0CF"],
      pressedFace: ["#ECE9D8", "#FFFFFF"],
      edge: "#003C74",
      glyph: "#4D6185",
      radius: 3,
      size: 17,
      bevel: { light: "#FFFFFF", dark: "#808080", width: 1 },
    },
  };
  slate.scroll = { track: "#F4F3EE", thumb: "#C0D0F8", thumbHover: "#D8E4FF", thumbEdge: "#003C74", thumbRadius: 3, width: 17 };
  slate.tabs = { variant: "xp", faceStops: ["#FFFFFF", "#ECE9D8"], markLineStops: ["#FFC83C", "#E5A01A"], markLine: "#E5A01A" };
  slate.slider = { variant: "pointer", thumbRadius: 2, ticks: 5, tickColor: "#808080", trackLight: "#FFFFFF" };
  slate.stepper = { arrows: true };
  fs.writeFileSync(file, JSON.stringify(slate, null, 2) + "\n");
  const files = generate(dir);
  assert.match(files.get("core/presets.lua"), /hoverFace = \{ "#FFFFFF", "#FFF0CF" \}/);
  assert.match(files.get("builder/src/theme/presets.generated.ts"), /hoverFace: \[ "#FFFFFF", "#FFF0CF" \]/);
  assert.match(files.get("core/presets.lua"), /thumbRadius = 3/);
  assert.match(files.get("builder/src/theme/presets.generated.ts"), /scroll: \{/);
});

test("the preset order lists the Windows ids after mac-dark and the Windows 11 ids last", () => {
  const dir = tempRoot();
  const slate = fs.readFileSync(path.join(dir, "themes", "presets", "slate.json"), "utf8");
  const ids = [
    "xp-luna", "xp-luna-silver", "xp-luna-olive", "xp-embedded", "xp-royale", "xp-royale-noir", "xp-zune",
    "windows-classic", "win11-light", "win11-dark",
  ];
  for (const id of ids) {
    fs.writeFileSync(path.join(dir, "themes", "presets", `${id}.json`), slate.replace('"id": "slate"', `"id": "${id}"`));
  }
  const text = generate(dir).get("builder/src/theme/presets.generated.ts");
  const order = /PRESET_ORDER: readonly string\[\] = \[([\s\S]*?)\];/.exec(text)[1].match(/"[^"]+"/g).map((s) => JSON.parse(s));
  assert.deepEqual(order.slice(order.indexOf("mac-dark")), ["mac-dark", ...ids]);
});
