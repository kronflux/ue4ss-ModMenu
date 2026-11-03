import { describe, expect, it } from "vitest";
import { emptyDocument } from "./defaults";
import { hostFixture } from "./fixture";
import { countItems, validateDocument } from "./validate";
import type { Item, MenuDocument } from "./types";

function clone(): MenuDocument {
  return structuredClone(hostFixture);
}

function messages(doc: unknown) {
  return validateDocument(doc).map((issue) => `${issue.path}: ${issue.message}`);
}

describe("validateDocument", () => {
  it("accepts the ModMenuHost fixture", () => {
    expect(validateDocument(hostFixture)).toEqual([]);
    expect(countItems(hostFixture)).toBeGreaterThan(20);
  });

  it("accepts an empty new menu", () => {
    expect(validateDocument(emptyDocument())).toEqual([]);
  });

  it("rejects a dropdown inside a row", () => {
    const doc = clone();
    const row = doc.sections[1].items[3];
    if (row.type !== "row") {
      throw new Error("expected Toggles row");
    }
    (row.items as unknown as Item[]).push({
      type: "dropdown",
      id: "bad",
      label: "Bad",
      options: ["A"],
    });
    expect(messages(doc).some((m) => m.includes("unsupported row child type 'dropdown'"))).toBe(true);
  });

  it("rejects a fold inside a fold", () => {
    const doc = clone();
    const fold = doc.sections[3].items.find((item) => item.type === "fold");
    if (!fold || fold.type !== "fold") {
      throw new Error("expected Give fold");
    }
    (fold.items as unknown as Item[]).push({
      type: "fold",
      id: "nested",
      label: "Nested",
      items: [{ type: "label", label: "nope" }],
    });
    expect(messages(doc).some((m) => m.includes("unsupported fold child type 'fold'"))).toBe(true);
  });

  it("rejects duplicate item ids in a section (including fold children)", () => {
    const doc = clone();
    const give = doc.sections[3];
    give.items.push({ type: "button", id: "giveAllBtn", label: "Dup" });
    expect(messages(doc).some((m) => m.includes("duplicate id 'giveAllBtn'"))).toBe(true);
  });

  it("rejects a tab that is not in Init.tabs", () => {
    const doc = clone();
    doc.sections[0].tab = "Missing";
    expect(messages(doc).some((m) => m.includes("tab Missing is not in Init"))).toBe(true);
  });

  it("rejects collapsed=true without collapsible", () => {
    const doc = clone();
    doc.sections[0].collapsed = true;
    expect(messages(doc).some((m) => m.includes("collapsed=true requires collapsible=true"))).toBe(true);
  });

  it("rejects empty dropdown options", () => {
    const doc = clone();
    const dropdown = doc.sections[1].items[2];
    if (dropdown.type !== "dropdown") {
      throw new Error("expected difficulty dropdown");
    }
    dropdown.options = [];
    expect(messages(doc).some((m) => m.includes("non-empty .options array"))).toBe(true);
  });

  it("rejects duplicate tab names", () => {
    const doc = clone();
    doc.init.tabs = ["Cheats", "Cheats"];
    expect(messages(doc).some((m) => m.includes("duplicate tab Cheats"))).toBe(true);
  });

  it("rejects duplicate section ids", () => {
    const doc = clone();
    doc.sections[1].id = "Status";
    expect(messages(doc).some((m) => m.includes("duplicate section id 'Status'"))).toBe(true);
  });

  it("rejects min > max", () => {
    const doc = clone();
    const row = doc.sections[1].items[3];
    if (row.type !== "row" || row.items[0].type !== "number") {
      throw new Error("expected heal number");
    }
    row.items[0].min = 10;
    row.items[0].max = 1;
    expect(messages(doc).some((m) => m.includes("min must be <= max"))).toBe(true);
  });
});

// These documents hold the three widgets added in milestone B. Each rule and message below
// matches the validate function of the same widget in widgets/slider.lua, widgets/radio.lua,
// widgets/keybind.lua and core/tooltip.lua, so the builder rejects what Register would reject.
function widgetDoc(items: unknown[]): MenuDocument {
  const doc = emptyDocument();
  doc.sections[0].items = items as Item[];
  return doc;
}

const slider = { type: "slider", id: "speed", label: "Speed", min: 0, max: 10, step: 0.5, default: 5 };
const radio = { type: "radio", id: "mode", label: "Mode", options: ["a", { label: "Bee", value: "b" }], default: "b" };
const keybind = { type: "keybind", id: "bind", label: "Bind", default: "LeftControl+F7", allowModifiers: true };

describe("validateDocument for slider, radio, keybind and tooltip", () => {
  it("accepts one slider, one radio, one keybind and one tooltip", () => {
    const doc = widgetDoc([slider, radio, keybind, { type: "button", id: "go", label: "Go", tooltip: "Runs it" }]);
    expect(messages(doc)).toEqual([]);
  });

  it("reports min when a slider has min greater than max", () => {
    const doc = widgetDoc([{ ...slider, min: 10, max: 1 }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: min must be less than max");
  });

  it("reports min equal to max, as the Lua widget does", () => {
    const doc = widgetDoc([{ ...slider, min: 3, max: 3 }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: min must be less than max");
  });

  it("requires slider min and max as numbers", () => {
    const doc = widgetDoc([{ type: "slider", id: "s", label: "S" }]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0]: min must be a number",
      "Register(Main) items[0]: max must be a number",
    ]);
  });

  it("rejects a slider step that is not positive and a default that is not numeric", () => {
    const doc = widgetDoc([{ ...slider, step: 0, default: "fast" }]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0]: step must be a positive number",
      "Register(Main) items[0]: default must be numeric",
    ]);
  });

  it("rejects slider integer, live and format of the wrong type", () => {
    const doc = widgetDoc([{ ...slider, integer: 1, live: "yes", format: 2 }]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0]: integer must be a boolean",
      "Register(Main) items[0]: live must be a boolean",
      "Register(Main) items[0]: format must be a string or a function",
    ]);
  });

  it("requires radio options", () => {
    const doc = widgetDoc([{ type: "radio", id: "r", label: "R" }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: radio requires an .options array");
  });

  it("requires at least one radio option", () => {
    const doc = widgetDoc([{ type: "radio", id: "r", label: "R", options: [] }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: radio requires at least one option");
  });

  it("rejects a radio default that no option holds, naming the values", () => {
    const doc = widgetDoc([{ ...radio, default: "z" }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: default must be one of a, b");
  });

  // Register accepts these, because core/options.lua turns each label and value into a string, and the export writes the same strings.
  it("accepts numeric radio option values and a numeric default that matches one", () => {
    const doc = widgetDoc([{ ...radio, options: [{ label: "One", value: 1 }, { value: 2 }], default: 1 }]);
    expect(messages(doc)).toEqual([]);
  });

  it("rejects a radio option table without label or value, and inline that is not a boolean", () => {
    const doc = widgetDoc([{ ...radio, options: ["a", {}], default: "a", inline: "yes" }]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0].options[1]: dropdown option needs .label or .value",
      "Register(Main) items[0]: inline must be a boolean",
    ]);
  });

  it("accepts an empty keybind default as no binding", () => {
    expect(messages(widgetDoc([{ ...keybind, default: "" }]))).toEqual([]);
  });

  it("rejects a keybind default that is not a string or does not parse", () => {
    const want = 'Register(Main) items[0]: default must be an FKey name string such as "F7" or "LeftControl+F7"';
    expect(messages(widgetDoc([{ ...keybind, default: 7 }]))).toEqual([want]);
    expect(messages(widgetDoc([{ ...keybind, default: "F7+LeftControl" }]))).toEqual([want]);
    expect(messages(widgetDoc([{ ...keybind, default: "Hyper+F7" }]))).toEqual([want]);
  });

  it("rejects keybind allowModifiers that is not a boolean", () => {
    const doc = widgetDoc([{ ...keybind, allowModifiers: "yes" }]);
    expect(messages(doc)).toEqual(["Register(Main) items[0]: allowModifiers must be a boolean"]);
  });

  it("rejects a tooltip that is not a string on any item, including a fold child", () => {
    const doc = widgetDoc([
      { type: "separator", tooltip: 3 },
      { type: "fold", id: "f", label: "F", items: [{ ...slider, tooltip: ["x"] }] },
    ]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0]: tooltip must be a string",
      "Register(Main) items[1].items[0]: tooltip must be a string",
    ]);
  });

  it("accepts a slider in a row and rejects a radio there, naming the allowed list", () => {
    const doc = widgetDoc([{ type: "row", items: [slider, radio] }]);
    expect(messages(doc)).toEqual([
      "Register(Main) items[0].items[1]: unsupported row child type 'radio' (button|checkbox|label|number|slider|textinput)",
    ]);
  });

  it("accepts slider, radio and keybind inside a fold", () => {
    const doc = widgetDoc([{ type: "fold", id: "f", label: "F", items: [slider, radio, keybind] }]);
    expect(messages(doc)).toEqual([]);
  });
});
