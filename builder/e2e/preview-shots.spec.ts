import { mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { expect, test } from "@playwright/test";
import { STORAGE_KEY, gotoFresh, preview } from "./helpers";

// Saves two preview PNGs per Windows preset, the top of the panel and the panel scrolled to its end.
// Run it with PREVIEW_SHOTS=1; any other run skips it.
const WINDOWS_PRESETS = [
  "xp-luna",
  "xp-luna-silver",
  "xp-luna-olive",
  "xp-embedded",
  "xp-royale",
  "xp-royale-noir",
  "xp-zune",
  "windows-classic",
];

const OUT_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../../../.hyperfocus/previews");

// Two tabs, every item type, enough items that the panel scrolls, and one disabled item.
function shotDocument(theme: string) {
  const filler = Array.from({ length: 14 }, (_, i) => ({
    type: "label",
    label: `Scroll filler line ${String(i + 1).padStart(2, "0")}`,
  }));
  return {
    version: 1,
    init: {
      title: "Preview Shot",
      instanceId: "PreviewShot",
      keyHint: "F8",
      dock: "left",
      theme,
      tabs: ["Main", "Other"],
    },
    sections: [
      {
        id: "Main",
        title: "Every control",
        tab: "Main",
        description: "One of each item type",
        items: [
          { type: "label", label: "A label with some text." },
          { type: "button", id: "go", label: "Default", tooltip: "A tooltip" },
          { type: "button", id: "ok", label: "Primary", variant: "primary" },
          { type: "button", id: "off", label: "Disabled button", enabled: false },
          { type: "checkbox", id: "chkOff", label: "Check box, off", default: false },
          { type: "checkbox", id: "chkOn", label: "Check box, on", default: true },
          { type: "radio", id: "rad", label: "Radio", options: ["Stand", "Crouch", "Prone"], default: "Crouch", inline: true },
          { type: "slider", id: "sld", label: "Slider", min: 0, max: 100, step: 10, default: 40, integer: true },
          { type: "dropdown", id: "drop", label: "Dropdown", options: ["Alpha", "Beta", "Gamma"], default: "Beta" },
          { type: "number", id: "num", label: "Number", default: 20, min: 0, max: 100, step: 5, integer: true },
          { type: "textinput", id: "txt", label: "Text", default: "hello" },
          { type: "keybind", id: "key", label: "Keybind", default: "F5" },
          { type: "stepper", id: "stp", label: "Stepper", min: 0, max: 10, step: 1, default: 3, integer: true },
          { type: "progress", id: "prg", label: "Progress", default: 0.6 },
          { type: "multiselect", id: "mul", label: "Multiselect", options: ["Red", "Green", "Blue"], default: ["Green"] },
          { type: "colorpicker", id: "col", label: "Colour", default: { R: 0.2, G: 0.5, B: 0.8, A: 1 } },
          { type: "separator" },
          ...filler,
          { type: "button", id: "last", label: "Last item" },
        ],
      },
      {
        id: "Second",
        title: "Second tab",
        tab: "Other",
        items: [{ type: "label", label: "Content of the second tab." }],
      },
    ],
  };
}

// Headless Chromium hides scrollbars by default; the shots show the themed bar.
test.use({ launchOptions: { ignoreDefaultArgs: ["--hide-scrollbars"] } });

test.describe("preview shots", () => {
  test.skip(process.env.PREVIEW_SHOTS !== "1", "set PREVIEW_SHOTS=1 to save the preview PNGs");

  for (const id of WINDOWS_PRESETS) {
    test(`save the preview of ${id}`, async ({ page }) => {
      await page.setViewportSize({ width: 1500, height: 1000 });
      await gotoFresh(page);
      // A preset whose file is not written yet has no option in the theme list; the run is skipped for it.
      await page.locator(".ed-tree-label").filter({ has: page.locator(".ed-tree-hint", { hasText: "init" }) }).click();
      const options = await page.getByLabel("Theme", { exact: true }).locator(`option[value="${id}"]`).count();
      test.skip(options === 0, `no preset ${id} yet`);

      await page.evaluate(([key, value]) => localStorage.setItem(key, value), [STORAGE_KEY, JSON.stringify(shotDocument(id))]);
      await page.reload();
      await expect(preview(page).locator(".mm-title")).toHaveText("Preview Shot");

      mkdirSync(OUT_DIR, { recursive: true });
      const panel = preview(page);
      await expect(panel.locator(".mm-scroll")).toBeVisible();
      await panel.screenshot({ path: resolve(OUT_DIR, `${id}.png`) });
      await panel.locator(".mm-scroll").evaluate((el) => {
        el.scrollTop = el.scrollHeight;
      });
      await panel.screenshot({ path: resolve(OUT_DIR, `${id}-scrolled.png`) });
    });
  }
});
