import { MODMENU_BUNDLE } from "virtual:modmenu-runtime";
import { describe, expect, it } from "vitest";
import { emptyDocument, hostFixture } from "../schema";
import type { Item } from "../schema";
import { hostFolderName, printLua } from "./lua";
import { hostZip } from "./hostZip";

describe("printLua", () => {
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
