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
