import { describe, expect, it } from "vitest";
import { emptyDocument, validateDocument } from "../schema";
import {
  addItem,
  addSection,
  addTab,
  addTarget,
  canAccept,
  ensureIds,
  getItem,
  idBase,
  idCollision,
  patchItem,
  removeNode,
  renameTab,
  resetItemLook,
  resetStyleField,
  setItemLook,
  setStyleBorrow,
  setStyleField,
  slugId,
  uniqueItemId,
} from "./model";

function itemId(doc: ReturnType<typeof emptyDocument>, sel: Extract<Parameters<typeof getItem>[1], { kind: "item" }>) {
  const item = getItem(doc, sel);
  return item && "id" in item ? item.id : undefined;
}

describe("editor model", () => {
  it("slugifies labels", () => {
    expect(slugId("God mode (mock)", "x")).toBe("godModeMock");
    expect(slugId("   ", "fallback")).toBe("fallback");
  });

  it("rejects dropdown in a row and fold in a fold", () => {
    expect(canAccept("row", "dropdown")).toBe(false);
    expect(canAccept("fold", "fold")).toBe(false);
    expect(canAccept("fold", "row")).toBe(true);
    expect(canAccept("row", "button")).toBe(true);
  });

  it("accepts a slider in a row and a slider, radio or keybind in a fold", () => {
    expect(canAccept("row", "slider")).toBe(true);
    expect(canAccept("row", "radio")).toBe(false);
    expect(canAccept("row", "keybind")).toBe(false);
    expect(canAccept("fold", "slider")).toBe(true);
    expect(canAccept("fold", "radio")).toBe(true);
    expect(canAccept("fold", "keybind")).toBe(true);
  });

  it("creates a valid slider, radio and keybind from the palette", () => {
    const slider = addItem(emptyDocument(), { kind: "section", index: 0 }, "slider");
    const radio = addItem(emptyDocument(), { kind: "section", index: 0 }, "radio");
    const keybind = addItem(emptyDocument(), { kind: "section", index: 0 }, "keybind");
    expect(slider && radio && keybind).toBeTruthy();
    if (!slider || !radio || !keybind) {
      return;
    }
    // The empty document starts with one hint label, so the added item is the second one.
    expect(slider.doc.sections[0].items[1]).toMatchObject({ type: "slider", min: 0, max: 100, default: 50, step: 1 });
    expect(radio.doc.sections[0].items[1]).toMatchObject({ type: "radio", options: ["A", "B"], default: "A" });
    expect(keybind.doc.sections[0].items[1]).toMatchObject({ type: "keybind", default: "" });
    for (const added of [slider, radio, keybind]) {
      expect(validateDocument(added.doc)).toEqual([]);
    }
  });

  it("adds a dropdown after a selected row, not inside it", () => {
    const seeded = addItem(emptyDocument(), { kind: "section", index: 0 }, "row");
    expect(seeded).not.toBeNull();
    if (!seeded) {
      return;
    }
    expect(addTarget(seeded.doc, seeded.selection, "dropdown")).toEqual({
      sectionIndex: 0,
      containerPath: [],
      parent: "section",
      insertAt: seeded.selection.kind === "item" ? seeded.selection.path[0] + 1 : -1,
    });
    expect(addTarget(seeded.doc, seeded.selection, "button")?.parent).toBe("row");
  });

  it("adds a fold after a selected fold, not inside it", () => {
    const seeded = addItem(emptyDocument(), { kind: "section", index: 0 }, "fold");
    expect(seeded).not.toBeNull();
    if (!seeded) {
      return;
    }
    expect(addTarget(seeded.doc, seeded.selection, "fold")?.parent).toBe("section");
    expect(addTarget(seeded.doc, seeded.selection, "checkbox")?.parent).toBe("fold");
  });

  it("uniqueItemId avoids collisions", () => {
    const section = emptyDocument().sections[0];
    section.items.push({ type: "button", id: "doThing", label: "A" });
    expect(uniqueItemId(section, "doThing")).toBe("doThing2");
  });

  it("renameTab updates section.tab", () => {
    let doc = emptyDocument();
    const tabbed = addTab(doc);
    doc = tabbed.doc;
    const sectioned = addSection(doc, tabbed.selection);
    doc = sectioned.doc;
    doc = renameTab(doc, 0, "Cheats");
    expect(doc.init.tabs).toEqual(["Cheats"]);
    expect(doc.sections[1].tab).toBe("Cheats");
  });

  it("remove tab clears section.tab and drops empty tabs list", () => {
    let doc = addTab(emptyDocument()).doc;
    doc.sections[0].tab = "Tab";
    const result = removeNode(doc, { kind: "tab", index: 0 });
    expect(result.doc.init.tabs).toBeUndefined();
    expect(result.doc.sections[0].tab).toBeUndefined();
  });

  it("builds ids from section and label", () => {
    const section = emptyDocument().sections[0];
    expect(idBase(section, "button", "Do thing")).toBe("main_doThing");
    expect(idBase(section, "checkbox", "")).toBe("main_checkbox");
  });

  it("ensureIds fills missing widget ids", () => {
    const doc = emptyDocument();
    doc.sections[0].items.push({ type: "button", id: "", label: "Heal" });
    const filled = ensureIds(doc);
    const button = filled.sections[0].items.find((item) => item.type === "button");
    expect(button && "id" in button && button.id).toBe("main_heal");
  });

  it("empty id patch regenerates; custom id is kept when the label changes", () => {
    let doc = emptyDocument();
    const added = addItem(doc, { kind: "section", index: 0 }, "button");
    expect(added).not.toBeNull();
    if (!added || added.selection.kind !== "item") {
      return;
    }
    doc = added.doc;
    expect(itemId(doc, added.selection)).toBe("main_doThing");
    doc = patchItem(doc, added.selection, { id: "" });
    expect(itemId(doc, added.selection)).toBe("main_doThing");
    doc = patchItem(doc, added.selection, { id: "myHeal" });
    doc = patchItem(doc, added.selection, { label: "Heal player" });
    expect(itemId(doc, added.selection)).toBe("myHeal");
    doc = patchItem(doc, added.selection, { id: "main_doThing" });
    doc = patchItem(doc, added.selection, { label: "Do thing" });
    doc = patchItem(doc, added.selection, { label: "Revive" });
    expect(itemId(doc, added.selection)).toBe("main_revive");
  });

  it("leaves a document without style or look untouched until a style is set", () => {
    const doc = emptyDocument();
    const reset = resetStyleField(doc, "button", "radius");
    expect("style" in reset.init).toBe(false);
  });

  it("idCollision ignores the item being edited", () => {
    const section = emptyDocument().sections[0];
    section.items = [
      { type: "button", id: "heal", label: "Heal" },
      { type: "button", id: "apply", label: "Apply" },
    ];
    expect(idCollision(section, "heal", [0])).toBe(false);
    expect(idCollision(section, "heal", [1])).toBe(true);
  });
});

// The expected values come from themes/presets: storm's accent is #F2B33D and its button radius 2;
// neon's button is a ghost pill with radius 1.
describe("style differences", () => {
  function storm() {
    const doc = emptyDocument();
    doc.init.theme = "storm";
    doc.sections[0].items.push({ type: "button", id: "go", label: "Go" });
    return doc;
  }
  const button: Extract<Parameters<typeof getItem>[1], { kind: "item" }> = { kind: "item", sectionIndex: 0, path: [1] };

  it("stores nothing when a field is set to the preset's own value", () => {
    const doc = setStyleField(storm(), "toggle", "trackOn", "#F2B33D");
    expect("style" in doc.init).toBe(false);
  });

  it("stores a field that differs, and removes it when set back to the preset's value", () => {
    const changed = setStyleField(storm(), "toggle", "trackOn", "#22F1FF");
    expect(changed.init.style).toEqual({ toggle: { trackOn: "#22F1FF" } });
    const back = setStyleField(changed, "toggle", "trackOn", "#F2B33D");
    expect("style" in back.init).toBe(false);
  });

  it("resets a field and removes the emptied tables", () => {
    const changed = setStyleField(storm(), "button", "radius", 5);
    expect(changed.init.style).toEqual({ button: { radius: 5 } });
    expect("style" in resetStyleField(changed, "button", "radius").init).toBe(false);
  });

  it("stores a borrow as the preset id, and drops a field the borrowed preset already has", () => {
    const borrowed = setStyleBorrow(storm(), "button", "neon");
    expect(borrowed.init.style).toEqual({ button: "neon" });
    expect(setStyleField(borrowed, "button", "radius", 1).init.style).toEqual({ button: "neon" });
    const withField = setStyleField(borrowed, "button", "radius", 5);
    // Neon's button is a pill, so the new radius also stores pill = false (the pill ruling).
    expect(withField.init.style).toEqual({ button: { from: "neon", radius: 5, pill: false } });
    expect(setStyleBorrow(withField, "button", null).init.style).toEqual({ button: { radius: 5, pill: false } });
  });

  it("stores no borrow that resolves the same as the theme", () => {
    // Storm's button has only a radius and no colours, so borrowing it from storm changes nothing.
    expect("style" in setStyleBorrow(storm(), "button", "storm").init).toBe(false);
  });

  it("keeps an earlier field when a later edit makes it equal its derived value", () => {
    // Storm's toggle.trackOn is derived from palette.accent. After accent changes to the same colour,
    // editing another toggle field must not drop trackOn, or a later accent change would move it.
    let doc = setStyleField(storm(), "toggle", "trackOn", "#22F1FF");
    doc = setStyleField(doc, "palette", "accent", "#22F1FF");
    doc = setStyleField(doc, "toggle", "knobOn", "#000000");
    expect(doc.init.style).toEqual({ palette: { accent: "#22F1FF" }, toggle: { trackOn: "#22F1FF", knobOn: "#000000" } });
  });

  it("keeps an earlier look field when another look field is edited", () => {
    let doc = setItemLook(storm(), button, "radius", 0);
    doc = setItemLook(doc, button, "height", 50);
    doc = setStyleField(doc, "button", "radius", 0);
    doc = setItemLook(doc, button, "height", 60);
    expect(getItem(doc, button)?.look).toEqual({ radius: 0, height: 60 });
  });

  it("turns pill off when radius is edited on a type that resolves as a pill", () => {
    // Neon's button is a pill, and a pill wins over radius, so the edit also stores pill = false.
    const borrowed = setStyleBorrow(storm(), "button", "neon");
    expect(setStyleField(borrowed, "button", "radius", 6).init.style).toEqual({ button: { from: "neon", radius: 6, pill: false } });
    // Storm's own button is no pill, so pill is left alone.
    expect(setStyleField(storm(), "button", "radius", 6).init.style).toEqual({ button: { radius: 6 } });
  });

  it("turns pill off when a look's radius is edited on an item that resolves as a pill", () => {
    const borrowed = setStyleBorrow(storm(), "button", "neon");
    expect(getItem(setItemLook(borrowed, button, "radius", 0), button)?.look).toEqual({ radius: 0, pill: false });
    expect(getItem(setItemLook(storm(), button, "radius", 0), button)?.look).toEqual({ radius: 0 });
  });

  it("stores palette colours that differ", () => {
    expect("style" in setStyleField(storm(), "palette", "accent", "#F2B33D").init).toBe(false);
    expect(setStyleField(storm(), "palette", "accent", "#FF0000").init.style).toEqual({ palette: { accent: "#FF0000" } });
  });

  it("stores an item look only where it differs from the item's resolved type", () => {
    const borrowed = setStyleBorrow(storm(), "button", "neon");
    expect(getItem(setItemLook(borrowed, button, "radius", 1), button)?.look).toBeUndefined();
    const looked = setItemLook(borrowed, button, "radius", 0);
    expect(getItem(looked, button)?.look).toEqual({ radius: 0, pill: false });
    // Resetting radius leaves the pill field the edit stored; resetting that too removes the look.
    const resetRadius = resetItemLook(looked, button, "radius");
    expect(getItem(resetRadius, button)?.look).toEqual({ pill: false });
    const reset = resetItemLook(resetRadius, button, "pill");
    expect(getItem(reset, button) && "look" in (getItem(reset, button) as object)).toBe(false);
  });

  it("builds the AC-11 document with only the three differences, and it validates", () => {
    let doc = setStyleBorrow(storm(), "button", "neon");
    doc = setStyleField(doc, "toggle", "trackOn", "#22F1FF");
    doc = setItemLook(doc, button, "radius", 0);
    expect(doc.init.theme).toBe("storm");
    expect(doc.init.style).toEqual({ button: "neon", toggle: { trackOn: "#22F1FF" } });
    // Neon's button is a pill, so the radius edit also stores pill = false (the pill ruling).
    expect(getItem(doc, button)).toEqual({ type: "button", id: "go", label: "Go", look: { radius: 0, pill: false } });
    expect(validateDocument(doc)).toEqual([]);
  });
});
