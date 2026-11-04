import { MODMENU_BUNDLE } from "virtual:modmenu-runtime";
import { describe, expect, it } from "vitest";
import { emptyDocument, hostFixture } from "../schema";
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