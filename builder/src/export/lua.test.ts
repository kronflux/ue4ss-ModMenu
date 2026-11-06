import { MODMENU_BUNDLE } from "virtual:modmenu-runtime";
import { describe, expect, it } from "vitest";
import { emptyDocument, hostFixture, validateDocument } from "../schema";
import { fullDocument } from "../schema/fullFixture";
import type { Item } from "../schema";
import { hostFolderName, printLua } from "./lua";
import { hostZip } from "./hostZip";

describe("printLua", () => {
  // The export of the shipped fixture is pinned in a file, so a change to any emitter that alters an existing
  // document fails here. The file was captured before milestone C task 6 and must not change with it (AC-15).
  it("exports the Host fixture exactly as it did before the new fields", async () => {
    await expect(printLua(hostFixture)).toMatchFileSnapshot("./__fixture-export.txt");
  });

  it("emits Init + Register for the Host fixture", () => {
    const lua = printLua(hostFixture);
    expect(lua).toContain('local ModMenu = require("ModMenu.ModMenu")');
    expect(lua).toContain('title = "ModMenu Host"');
    expect(lua).toContain("key = Key.F8");
    expect(lua).toContain('tabs = { "Cheats", "Give", "Keybinds" }');
    expect(lua).toContain('id = "Toggles"');
    expect(lua).toContain('id = "Give"');
    expect(lua).toContain("onChange = function(on)");
    expect(lua).toContain("onClick = function()");
    expect(lua).toContain("-- TODO: game call");
    expect(lua).toContain("ModMenu Host Loaded");
    expect(lua).toContain("F8 = toggle menu");
    expect(lua).toContain("Tabs: Cheats / Give / Keybinds");
    expect(lua).toContain("Dock: left");
    expect(lua).toContain("shared/ModMenu/");
    expect(lua).not.toMatch(/not bundled here/);
    expect(lua).not.toMatch(/ModMenu\.SetOptions\(/);
    expect(lua).not.toMatch(/ModMenu\.OnOpen\(/);
  });

  it("emits Key from a plain keyHint", () => {
    const lua = printLua(emptyDocument());
    expect(lua).toContain("key = Key.F6");
    expect(lua).toContain("My Mod Menu Loaded");
    expect(lua).toContain('id = "Main"');
    expect(hostFolderName(emptyDocument())).toBe("MyMod");
  });

  it("comments when keyHint is not a Key name", () => {
    const doc = emptyDocument();
    doc.init.keyHint = "Left Alt";
    const lua = printLua(doc);
    expect(lua).toContain("-- TODO: set key / keyName by hand");
    expect(lua).not.toContain("key = Key.");
  });
});

describe("printLua for slider, radio, keybind and tooltip", () => {
  function widgetLua(items: unknown[]): string {
    const doc = emptyDocument();
    doc.sections[0].items = items as Item[];
    return printLua(doc);
  }

  it("exports a slider with its range, step and flags", () => {
    const lua = widgetLua([
      { type: "slider", id: "speed", label: "Speed", min: 0, max: 10, step: 0.5, default: 5, integer: false, live: true, format: "%.1f" },
    ]);
    expect(lua).toContain('type = "slider",');
    expect(lua).toContain('id = "speed",');
    expect(lua).toContain("default = 5,");
    expect(lua).toContain("min = 0,");
    expect(lua).toContain("max = 10,");
    expect(lua).toContain("step = 0.5,");
    expect(lua).toContain("live = true,");
    expect(lua).toContain('format = "%.1f",');
    expect(lua).not.toContain("integer =");
    expect(lua).toContain("onChange = function(value)");
  });

  it("exports a radio with its options, default and inline", () => {
    const lua = widgetLua([
      { type: "radio", id: "mode", label: "Mode", options: ["a", { label: "Bee", value: "b" }], default: "b", inline: true },
    ]);
    expect(lua).toContain('type = "radio",');
    expect(lua).toContain('{ label = "Bee", value = "b" },');
    expect(lua).toContain('default = "b",');
    expect(lua).toContain("inline = true,");
    expect(lua).toContain("onChange = function(value)");
  });

  // Options.NormalizeOptions in core/options.lua turns every label and value into a string with tostring.
  it("exports numeric radio option values and default as strings", () => {
    const lua = widgetLua([
      { type: "radio", id: "level", label: "Level", options: [{ label: "One", value: 1 }, { value: 2 }], default: 1 },
    ]);
    expect(lua).toContain('{ label = "One", value = "1" },');
    expect(lua).toMatch(/\n\s+"2",\n/);
    expect(lua).toContain('default = "1",');
  });

  it("exports a keybind with its default and allowModifiers", () => {
    const lua = widgetLua([{ type: "keybind", id: "bind", label: "Bind", default: "LeftControl+F7", allowModifiers: true }]);
    expect(lua).toContain('type = "keybind",');
    expect(lua).toContain('default = "LeftControl+F7",');
    expect(lua).toContain("allowModifiers = true,");
    expect(lua).toContain("onChange = function(binding)");
  });

  it("exports a stepper with its range, step, flags and an onChange stub", () => {
    const lua = widgetLua([
      { type: "stepper", id: "count", label: "Count", min: 0, max: 10, step: 2, default: 4, integer: true, format: "%d x" },
    ]);
    expect(lua).toContain('type = "stepper",');
    expect(lua).toContain('id = "count",');
    expect(lua).toContain("default = 4,");
    expect(lua).toContain("min = 0,");
    expect(lua).toContain("max = 10,");
    expect(lua).toContain("step = 2,");
    expect(lua).toContain("integer = true,");
    expect(lua).toContain('format = "%d x",');
    expect(lua).toContain("onChange = function(value)");
  });

  it("writes only the stepper fields that are set", () => {
    const lua = widgetLua([{ type: "stepper", id: "bare", label: "Bare" }]);
    expect(lua).toContain('type = "stepper",');
    for (const field of ["default =", "min =", "max =", "step =", "integer =", "format ="]) {
      expect(lua).not.toContain(field);
    }
  });

  it("exports a progress bar with its range, format and variant, and no onChange stub", () => {
    const lua = widgetLua([
      { type: "progress", id: "load", label: "Load", min: 0, max: 100, default: 25, format: "%d of 100", variant: "success" },
    ]);
    expect(lua).toContain('type = "progress",');
    expect(lua).toContain('id = "load",');
    expect(lua).toContain("default = 25,");
    expect(lua).toContain("min = 0,");
    expect(lua).toContain("max = 100,");
    expect(lua).toContain('format = "%d of 100",');
    expect(lua).toContain('variant = "success",');
    expect(lua).not.toContain("onChange");
  });

  it("writes only the progress fields that are set", () => {
    const lua = widgetLua([{ type: "progress", id: "bare", label: "Bare" }]);
    expect(lua).toContain('type = "progress",');
    for (const field of ["default =", "min =", "max =", "format =", "variant ="]) {
      expect(lua).not.toContain(field);
    }
  });

  it("leaves out a default variant, as a button does", () => {
    const lua = widgetLua([{ type: "progress", id: "p", label: "P", variant: "default" }]);
    expect(lua).not.toContain("variant =");
  });

  it("exports a multiselect with its options, default array, columns and an onChange stub", () => {
    const lua = widgetLua([
      { type: "multiselect", id: "tags", label: "Tags", options: ["a", { label: "Bee", value: "b" }, "c"], default: ["a", "c"], columns: 2 },
    ]);
    expect(lua).toContain('type = "multiselect",');
    expect(lua).toContain('id = "tags",');
    expect(lua).toContain('{ label = "Bee", value = "b" },');
    expect(lua).toContain('default = { "a", "c" },');
    expect(lua).toContain("columns = 2,");
    expect(lua).toContain("onChange = function(values)");
  });

  it("writes only the multiselect fields that are set, and an empty default as an empty table", () => {
    const bare = widgetLua([{ type: "multiselect", id: "bare", label: "Bare", options: ["a"] }]);
    expect(bare).toContain('type = "multiselect",');
    expect(bare).not.toContain("default =");
    expect(bare).not.toContain("columns =");
    const empty = widgetLua([{ type: "multiselect", id: "none", label: "None", options: ["a"], default: [] }]);
    expect(empty).toContain("default = {},");
  });

  it("exports numeric multiselect option values as strings, which a default entry then names", () => {
    const lua = widgetLua([
      { type: "multiselect", id: "levels", label: "Levels", options: [{ label: "One", value: 1 }, { value: 2 }], default: ["1"] },
    ]);
    expect(lua).toContain('{ label = "One", value = "1" },');
    expect(lua).toContain('default = { "1" },');
  });

  it("exports a colorpicker with its default colour, alpha and an onChange stub", () => {
    const lua = widgetLua([
      { type: "colorpicker", id: "tint", label: "Tint", default: { R: 1, G: 0.5, B: 0, A: 0.25 }, alpha: false },
    ]);
    expect(lua).toContain('type = "colorpicker",');
    expect(lua).toContain('id = "tint",');
    expect(lua).toContain("default = { R = 1, G = 0.5, B = 0, A = 0.25 },");
    expect(lua).toContain("alpha = false,");
    expect(lua).toContain("onChange = function(color)");
  });

  it("writes only the colorpicker fields that are set, and leaves out alpha when it is on", () => {
    const bare = widgetLua([{ type: "colorpicker", id: "bare", label: "Bare" }]);
    expect(bare).toContain('type = "colorpicker",');
    expect(bare).not.toContain("default =");
    expect(bare).not.toContain("alpha =");
    const on = widgetLua([{ type: "colorpicker", id: "on", label: "On", alpha: true }]);
    expect(on).not.toContain("alpha =");
  });

  it("writes no colorpicker default whose channel holds text", () => {
    const code = "0 }, onChange = os.execute('x'), y = {";
    const lua = widgetLua([{ type: "colorpicker", id: "bad", label: "Bad", default: { R: code, G: 0, B: 0, A: 1 } }]);
    expect(lua).not.toContain("os.execute");
    expect(lua).not.toContain("default =");
  });

  it("exports tooltip on a plain item, a separator and a fold child", () => {
    const lua = widgetLua([
      { type: "button", id: "go", label: "Go", tooltip: 'Runs "it"' },
      { type: "separator", tooltip: "Gap" },
      { type: "fold", id: "f", label: "F", tooltip: "More", items: [{ type: "keybind", id: "k", label: "K", tooltip: "Bind it" }] },
    ]);
    expect(lua).toContain('tooltip = "Runs \\"it\\"",');
    expect(lua).toContain('{ type = "separator", tooltip = "Gap" },');
    expect(lua).toContain('tooltip = "More",');
    expect(lua).toContain('tooltip = "Bind it",');
  });
});

describe("hostZip", () => {
  it("builds a zip with the host folder and shared/ModMenu", () => {
    const { filename, bytes } = hostZip(emptyDocument());
    expect(filename).toBe("MyMod.zip");
    expect(bytes[0]).toBe(0x50);
    expect(bytes[1]).toBe(0x4b);
    const asText = new TextDecoder().decode(bytes);
    expect(asText).toContain("MyMod/enabled.txt");
    expect(asText).toContain("MyMod/Scripts/main.lua");
    expect(asText).toContain("shared/ModMenu/ModMenu.lua");
    expect(asText).toContain("ModMenu.Init");
    expect(asText).toContain("ModMenu.bundle.lua");
    expect(MODMENU_BUNDLE).toContain("package.preload");
    expect(MODMENU_BUNDLE).toContain("ModMenu.core.util");
  });
});

// A document with every optional field set exports each of them, and an unset field exports nothing.
describe("printLua for every setting the library reads", () => {
  function fullDocument() {
    const doc = emptyDocument();
    Object.assign(doc.init, {
      tooltipDelayMs: 250,
      showClose: false,
      cursorScale: 2,
      spacing: { gapItem: 4, panelPad: 10 },
    });
    Object.assign(doc.sections[0], { description: "A line", prefix: "[x]", collapsible: true });
    doc.sections[0].items = [
      { type: "label", label: "L", align: "center", wrap: false, style: "heading", enabled: false, visible: false },
      { type: "checkbox", id: "c", label: "C", showState: false, visible: false },
      { type: "number", id: "n", label: "N", step: 5, prefix: "$", suffix: "ms", debounceMs: 100, enabled: false },
      { type: "textinput", id: "t", label: "T", debounceMs: 0, maxLength: 8 },
      { type: "slider", id: "s", label: "S", min: 0, max: 10, showValue: false, labelWidth: 80 },
      { type: "separator", visible: false },
      { type: "row", enabled: false, items: [{ type: "button", id: "b", label: "B", visible: false }] },
      { type: "fold", id: "f", label: "F", visible: false, items: [{ type: "label", label: "in" }] },
    ] as unknown as Item[];
    return doc;
  }

  const expected = [
    "tooltipDelayMs = 250,",
    "showClose = false,",
    "cursorScale = 2,",
    "spacing = {",
    "gapItem = 4,",
    "panelPad = 10,",
    'description = "A line",',
    'prefix = "[x]",',
    'align = "center",',
    "wrap = false,",
    'style = "heading",',
    "showState = false,",
    "step = 5,",
    'prefix = "$",',
    'suffix = "ms",',
    "debounceMs = 100,",
    "debounceMs = 0,",
    "maxLength = 8,",
    "showValue = false,",
    "labelWidth = 80,",
    '{ type = "separator", visible = false },',
  ];

  for (const line of expected) {
    it(`writes ${line}`, () => {
      expect(printLua(fullDocument())).toContain(line);
    });
  }

  it("writes enabled = false and visible = false on a label, a row, a fold and a number", () => {
    const lua = printLua(fullDocument());
    expect(lua.match(/enabled = false,/g)?.length).toBe(3);
    expect(lua.match(/visible = false,/g)?.length).toBe(4);
  });

  it("writes nothing for a field left unset", () => {
    const lua = printLua(emptyDocument());
    for (const word of ["tooltipDelayMs", "showClose", "cursorScale", "spacing", "description", "enabled", "visible"]) {
      expect(lua).not.toContain(word);
    }
  });

  it("writes no field whose number holds text, so an imported document cannot put code into the Lua", () => {
    const doc = emptyDocument();
    const code = "1, onChange = os.execute('x')";
    Object.assign(doc.init, { tooltipDelayMs: code, cursorScale: code, spacing: { gapItem: code, tabPad: 6 } });
    doc.sections[0].items = [
      { type: "number", id: "n", label: "N", default: code, min: code, step: code, fieldWidth: code },
      { type: "textinput", id: "t", label: "T", maxLength: code },
      { type: "slider", id: "s", label: "S", min: 0, max: code, default: code },
      { type: "dropdown", id: "d", label: "D", options: ["a"], maxVisible: code },
    ] as unknown as Item[];
    const lua = printLua(doc);
    expect(lua).not.toContain("os.execute");
    expect(lua).toContain("tabPad = 6,");
  });
});
describe("printLua keeps the order of an existing button", () => {
  it("writes variant, then enabled, then active", () => {
    const doc = emptyDocument();
    doc.sections[0].items = [
      { type: "button", id: "b", label: "B", variant: "danger", enabled: false, active: true },
    ] as unknown as Item[];
    const lua = printLua(doc);
    expect(lua.indexOf('variant = "danger"')).toBeLessThan(lua.indexOf("enabled = false"));
    expect(lua.indexOf("enabled = false")).toBeLessThan(lua.indexOf("active = true"));
  });
});
// AC-11 and AC-12: the theme, the style differences and each item's look reach Init and Register.
describe("printLua for themes, styles and looks", () => {
  function themed() {
    const doc = emptyDocument();
    doc.init.theme = "storm";
    // Written in reverse order, so the test shows the export sorts the keys.
    doc.init.style = { toggle: { trackOn: "#22F1FF" }, button: "neon" };
    doc.sections[0].items = [{ type: "button", id: "go", label: "Go", look: { radius: 0, pill: false } }] as Item[];
    return doc;
  }

  it("the AC-11 document is valid for the builder", () => {
    expect(validateDocument(themed())).toEqual([]);
  });

  it("writes the theme, the style table and the item look", () => {
    const lua = printLua(themed());
    expect(lua).toContain('    theme = "storm",\n');
    expect(lua).toContain(
      ['    style = {', '        button = "neon",', '        toggle = { trackOn = "#22F1FF" },', "    },"].join("\n"),
    );
    expect(lua).toContain('        look = { pill = false, radius = 0 },\n');
  });

  // The Lua suite runs this file through Config.ApplyInit and Registry.Register (builder_export_spec.lua).
  it("exports the AC-11 document to the Lua suite's fixture", async () => {
    await expect(printLua(themed())).toMatchFileSnapshot("../../../tooling/lua/fixtures/builder_theme_export.lua");
  });

  it("writes the item look after the item's other fields, before it closes", () => {
    const lua = printLua(themed());
    expect(lua.indexOf("onClick = function()")).toBeLessThan(lua.indexOf("look = { pill = false, radius = 0 }"));
  });

  it("writes a borrow with fields, a palette, nested tables, lists and colour tables", () => {
    const doc = emptyDocument();
    doc.init.style = {
      palette: { accent: "#FF0000", bg: { R: 0.1, G: 0.2, B: 0.3, A: 1 } },
      button: { from: "neon", radius: [1, 2, 3, 4], roles: { primary: { fill: "#00FF00" } }, upper: true },
      title: { font: ["kanit", "roboto"], shadow: false },
    };
    const lua = printLua(doc);
    expect(lua).toContain('        button = { from = "neon", radius = { 1, 2, 3, 4 }, roles = { primary = { fill = "#00FF00" } }, upper = true },');
    expect(lua).toContain('        palette = { accent = "#FF0000", bg = { R = 0.1, G = 0.2, B = 0.3, A = 1 } },');
    expect(lua).toContain('        title = { font = { "kanit", "roboto" }, shadow = false },');
  });

  it("writes nothing for an empty style or look", () => {
    const doc = emptyDocument();
    doc.init.style = {};
    doc.sections[0].items = [{ type: "button", id: "go", label: "Go", look: {} }] as Item[];
    const lua = printLua(doc);
    expect(lua).not.toContain("style =");
    expect(lua).not.toContain("look =");
  });

  it("writes no text from an imported style as code", () => {
    const doc = emptyDocument();
    const code = "1, onChange = os.execute('x')";
    doc.init.style = {
      button: { radius: Number.NaN, width: Infinity, edge: `"${code}`, [`a"] = os.execute('y') --`]: 1 },
    } as unknown as typeof doc.init.style;
    doc.sections[0].items = [{ type: "button", id: "go", label: "Go", look: { height: code, end: 2 } }] as unknown as Item[];
    const lua = printLua(doc);
    // Three occurrences, each inside one of the quoted strings checked below.
    expect(lua.match(/os\.execute/g)?.length).toBe(3);
    expect(lua).toContain('["a\\"] = os.execute(\'y\') --"] = 1');
    expect(lua).toContain('edge = "\\"1, onChange = os.execute(\'x\')"');
    expect(lua).toContain('look = { ["end"] = 2, height = "1, onChange = os.execute(\'x\')" },');
    expect(lua).not.toContain("radius =");
    expect(lua).not.toContain("width =");
  });
});

// The Lua suite loads these two files and runs them through the library's own checks, so they are written
// from the builder here and a change to either export shows up as a changed file in the diff.
describe("printLua output for the library's own checks", () => {
  it("the full document is valid for the builder", () => {
    expect(validateDocument(fullDocument())).toEqual([]);
  });

  it("exports the full document to the Lua suite's fixture", async () => {
    await expect(printLua(fullDocument())).toMatchFileSnapshot("../../../tooling/lua/fixtures/builder_full_export.lua");
  });

  it("exports the Host fixture to the Lua suite's fixture", async () => {
    await expect(printLua(hostFixture)).toMatchFileSnapshot("../../../tooling/lua/fixtures/builder_host_export.lua");
  });
});