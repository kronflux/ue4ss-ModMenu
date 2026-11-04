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
    const row = doc.sections[1].items.find((item) => item.type === "row");
    if (row === undefined || row.type !== "row") {
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
    const row = doc.sections[1].items.find((item) => item.type === "row");
    if (row === undefined || row.type !== "row" || row.items[0].type !== "number") {
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
      "Register(Main) items[0].items[1]: unsupported row child type 'radio' (button|checkbox|label|number|progress|slider|stepper|textinput)",
    ]);
  });

  it("accepts slider, radio and keybind inside a fold", () => {
    const doc = widgetDoc([{ type: "fold", id: "f", label: "F", items: [slider, radio, keybind] }]);
    expect(messages(doc)).toEqual([]);
  });
});

// The messages below are the ones the Lua widgets raise after their `Register(<section>) items[<n>]` prefix.
describe("validateDocument for enabled, visible and the presentation fields", () => {
  const cases: Array<[string, unknown, string]> = [
    ["enabled on a checkbox", { type: "checkbox", id: "c", label: "C", enabled: "no" }, "enabled must be a boolean"],
    ["visible on a checkbox", { type: "checkbox", id: "c", label: "C", visible: 1 }, "visible must be a boolean"],
    ["visible on a separator", { type: "separator", visible: "no" }, "visible must be a boolean"],
    ["label style", { type: "label", label: "L", style: "loud" }, "style must be one of normal, muted, heading, warning"],
    ["label align", { type: "label", label: "L", align: "middle" }, "align must be one of left, center, right"],
    ["label wrap", { type: "label", label: "L", wrap: "yes" }, "wrap must be a boolean"],
    ["slider showValue", { ...slider, showValue: "x" }, "showValue must be a boolean"],
    ["slider labelWidth", { ...slider, labelWidth: 0 }, "labelWidth must be a positive number"],
    ["number step", { type: "number", id: "n", label: "N", step: 0 }, "step must be a positive number"],
    ["number prefix", { type: "number", id: "n", label: "N", prefix: 3 }, "prefix must be a string"],
    ["number suffix", { type: "number", id: "n", label: "N", suffix: 3 }, "suffix must be a string"],
  ];

  for (const [name, item, message] of cases) {
    it(`reports ${name}`, () => {
      expect(messages(widgetDoc([item]))).toContain(`Register(Main) items[0]: ${message}`);
    });
  }

  it("accepts a fractional number step", () => {
    expect(messages(widgetDoc([{ type: "number", id: "n", label: "N", step: 0.5 }]))).toEqual([]);
  });

  it("reports a section description and prefix that are not strings", () => {
    const doc = emptyDocument();
    (doc.sections[0] as unknown as Record<string, unknown>).description = 3;
    (doc.sections[0] as unknown as Record<string, unknown>).prefix = 3;
    expect(messages(doc)).toEqual([
      "Register(Main): description must be a string",
      "Register(Main): prefix must be a string",
    ]);
  });

  it("accepts every field set to a valid value", () => {
    const doc = widgetDoc([
      { type: "label", label: "L", align: "center", wrap: false, style: "heading", enabled: false, visible: false },
      { ...slider, showValue: false, labelWidth: 80, enabled: true },
      { type: "number", id: "n", label: "N", step: 5, prefix: "$", suffix: "ms", visible: true },
      { type: "separator", visible: true },
    ]);
    (doc.sections[0] as unknown as Record<string, unknown>).description = "Muted line";
    (doc.sections[0] as unknown as Record<string, unknown>).prefix = "[tag]";
    expect(messages(doc)).toEqual([]);
  });
});

// The messages follow Stepper.validate in widgets/stepper.lua.
describe("validateDocument for the stepper", () => {
  const stepper = { type: "stepper", id: "count", label: "Count", min: 0, max: 10, step: 2, default: 4, integer: true, format: "%d" };

  it("accepts a full stepper and one with no range", () => {
    expect(messages(widgetDoc([stepper, { type: "stepper", id: "bare", label: "Bare" }]))).toEqual([]);
  });

  const cases: Array<[string, unknown, string]> = [
    ["min", { ...stepper, min: "a" }, "min must be a number"],
    ["max", { ...stepper, max: "a" }, "max must be a number"],
    ["an equal min and max", { ...stepper, min: 3, max: 3 }, "min must be less than max"],
    ["an inverted range", { ...stepper, min: 9, max: 1 }, "min must be less than max"],
    ["a zero step", { ...stepper, step: 0 }, "step must be a positive number"],
    ["a text step", { ...stepper, step: "a" }, "step must be a positive number"],
    ["a default that is not numeric", { ...stepper, default: "loud" }, "default must be numeric"],
    ["integer", { ...stepper, integer: 1 }, "integer must be a boolean"],
    ["format", { ...stepper, format: 3 }, "format must be a string"],
    ["enabled", { ...stepper, enabled: "no" }, "enabled must be a boolean"],
  ];
  for (const [name, item, message] of cases) {
    it(`reports ${name}`, () => {
      expect(messages(widgetDoc([item]))).toEqual([`Register(Main) items[0]: ${message}`]);
    });
  }

  it("requires an id and a label", () => {
    expect(messages(widgetDoc([{ type: "stepper" }]))).toEqual([
      "Register(Main) items[0]: requires .id",
      "Register(Main) items[0]: requires .label",
    ]);
  });

  it("accepts a stepper in a row and in a fold", () => {
    const doc = widgetDoc([
      { type: "row", items: [stepper] },
      { type: "fold", id: "f", label: "F", items: [{ ...stepper, id: "inFold" }] },
    ]);
    expect(messages(doc)).toEqual([]);
  });
});

// The messages follow Progress.validate in widgets/progress.lua. A missing min is 0 and a missing max is 1.
describe("validateDocument for the progress bar", () => {
  const progress = { type: "progress", id: "load", label: "Load", min: 0, max: 100, default: 25, format: "%d%%", variant: "success" };

  it("accepts a full progress item and a bare one", () => {
    expect(messages(widgetDoc([progress, { type: "progress", id: "bare", label: "Bare" }]))).toEqual([]);
  });

  const cases: Array<[string, unknown, string]> = [
    ["min", { ...progress, min: "a" }, "min must be a number"],
    ["max", { ...progress, max: "a" }, "max must be a number"],
    ["an equal min and max", { ...progress, min: 3, max: 3 }, "min must be less than max"],
    ["an inverted range", { ...progress, min: 9, max: 1 }, "min must be less than max"],
    ["a min that is not below the default max of 1", { type: "progress", id: "p", label: "P", min: 2 }, "min must be less than max"],
    ["a default that is not numeric", { ...progress, default: "loud" }, "default must be numeric"],
    ["format", { ...progress, format: 3 }, "format must be a string or a function"],
    ["variant", { ...progress, variant: "loud" }, "variant must be default|primary|secondary|success|danger|warning|info"],
    ["enabled", { ...progress, enabled: "no" }, "enabled must be a boolean"],
  ];
  for (const [name, item, message] of cases) {
    it(`reports ${name}`, () => {
      expect(messages(widgetDoc([item]))).toEqual([`Register(Main) items[0]: ${message}`]);
    });
  }

  it("requires an id and a label", () => {
    expect(messages(widgetDoc([{ type: "progress" }]))).toEqual([
      "Register(Main) items[0]: requires .id",
      "Register(Main) items[0]: requires .label",
    ]);
  });

  it("accepts a progress item in a row and in a fold", () => {
    const doc = widgetDoc([
      { type: "row", items: [progress] },
      { type: "fold", id: "f", label: "F", items: [{ ...progress, id: "inFold" }] },
    ]);
    expect(messages(doc)).toEqual([]);
  });
});

describe("validateDocument for the Init options the library reads", () => {
  function withInit(patch: Record<string, unknown>) {
    const doc = emptyDocument();
    Object.assign(doc.init, patch);
    return messages(doc);
  }

  it("accepts every Init option set to a valid value", () => {
    expect(withInit({ tooltipDelayMs: 0, showClose: false, cursorScale: 1.5, spacing: { gapItem: 0, panelPad: 12 } })).toEqual([]);
  });

  it("reports each bad Init option with the library's wording", () => {
    expect(withInit({ tooltipDelayMs: -1 })).toEqual(["init.tooltipDelayMs: must be a number of zero or more"]);
    expect(withInit({ cursorScale: 0.5 })).toEqual(["init.cursorScale: must be a number >= 1"]);
    expect(withInit({ showClose: "no" })).toEqual(["init.showClose: must be a boolean"]);
    expect(withInit({ spacing: 3 })).toEqual(["init.spacing: must be an object of numbers"]);
    expect(withInit({ spacing: { gapItem: -2 } })).toEqual(["init.spacing.gapItem: must be a number of zero or more"]);
    expect(withInit({ spacing: { nope: 2 } })).toEqual(["init.spacing.nope: is not a known spacing key"]);
  });

  it("reports a checkbox showState that is not a boolean", () => {
    const doc = widgetDoc([{ type: "checkbox", id: "c", label: "C", showState: "no" }]);
    expect(messages(doc)).toContain("Register(Main) items[0]: showState must be a boolean");
  });
});