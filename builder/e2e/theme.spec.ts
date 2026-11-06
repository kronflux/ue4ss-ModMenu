import { expect, test } from "@playwright/test";
import { STORAGE_KEY, gotoFresh, preview } from "./helpers";

// AC-11: pick a preset, borrow one object type, change one field and one item's look, then export.
test("edit, borrow and export a theme style", async ({ page, context }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await gotoFresh(page);
  await page.locator(".ed-tree-label").filter({ has: page.locator(".ed-tree-hint", { hasText: "init" }) }).click();

  await page.getByLabel("Theme", { exact: true }).selectOption("storm");
  await page.locator('details[data-type="button"] > summary').click();
  await page.getByLabel("button borrows from", { exact: true }).selectOption("neon");
  await page.locator('details[data-type="toggle"] > summary').click();
  await page.getByLabel("toggle.trackOn", { exact: true }).fill("#22F1FF");

  await page.locator(".ed-chips").getByRole("button", { name: "Button", exact: true }).click();
  await page.locator('details[data-type="look"] > summary').click();
  await page.getByLabel("look.radius", { exact: true }).fill("0");

  // The document holds the preset id and only the three differences.
  await expect
    .poll(async () => {
      const text = await page.evaluate((key) => localStorage.getItem(key), STORAGE_KEY);
      const doc = JSON.parse(text ?? "{}");
      const looks = doc.sections?.[0]?.items?.filter((item: { look?: unknown }) => item.look !== undefined);
      return { theme: doc.init?.theme, style: doc.init?.style, looks };
    }, { timeout: 3000 })
    .toEqual({
      theme: "storm",
      style: { button: "neon", toggle: { trackOn: "#22F1FF" } },
      // Neon's button is a pill, so the radius edit also stores pill = false.
      looks: [expect.objectContaining({ type: "button", look: { radius: 0, pill: false } })],
    });

  await page.getByRole("button", { name: "Copy Lua" }).click();
  await expect(page.getByRole("button", { name: "Copied Lua" })).toBeVisible();
  // The Windows clipboard turns each line ending into CRLF.
  const lua = (await page.evaluate(() => navigator.clipboard.readText())).replace(/\r\n/g, "\n");
  expect(lua).toContain('    theme = "storm",\n');
  expect(lua).toContain(
    ['    style = {', '        button = "neon",', '        toggle = { trackOn = "#22F1FF" },', "    },"].join("\n"),
  );
  expect(lua).toContain("        look = { pill = false, radius = 0 },\n");

  // Neon's button is a ghost pill, drawn in Storm's palette.
  await expect(preview(page).locator(".mm-variant-button-ghost").first()).toBeVisible();

  // A second button, without a look, draws as neon's pill. It adds no difference to the document.
  await page.locator(".ed-chips").getByRole("button", { name: "Button", exact: true }).click();
  const buttons = preview(page).locator(".mm-btn.mm-variant-button-ghost").filter({ hasText: "Do thing" });
  await expect(buttons).toHaveCount(2);
  await expect(buttons.nth(1)).toHaveCSS("border-top-left-radius", "999px");
  // The first button's look, radius 0 with pill off, gives it square corners.
  await expect(buttons.nth(0)).toHaveCSS("border-top-left-radius", "0px");
});

// Stage 2: the window frame shows in the preview, and a variant and a compound field are edited.
test("edit the stage 2 fields of mac-light", async ({ page }) => {
  await gotoFresh(page);
  await page.locator(".ed-tree-label").filter({ has: page.locator(".ed-tree-hint", { hasText: "init" }) }).click();

  await page.getByLabel("Theme", { exact: true }).selectOption("mac-light");
  await expect(preview(page).locator(".mm-lights")).toBeVisible();

  await page.locator('details[data-type="button"] > summary').click();
  await page.getByLabel("button.variant", { exact: true }).selectOption("classic");
  await expect
    .poll(async () => {
      const text = await page.evaluate((key) => localStorage.getItem(key), STORAGE_KEY);
      const doc = JSON.parse(text ?? "{}");
      return { theme: doc.init?.theme, style: doc.init?.style };
    }, { timeout: 3000 })
    .toEqual({ theme: "mac-light", style: { button: { variant: "classic" } } });

  // A bad compound value shows the validator's message and is not stored.
  await page.locator('details[data-type="header"] > summary').click();
  const stops = page.getByLabel("header.barStops", { exact: true });
  await stops.fill('["#000080"]');
  await expect(page.locator(".ed-style-error").filter({ hasText: "barStops" })).toBeVisible();
  // The rejected value is not stored.
  const stored = await page.evaluate((key) => localStorage.getItem(key), STORAGE_KEY);
  expect(JSON.parse(stored ?? "{}").init?.style?.header).toBeUndefined();
  await stops.fill('["#000080", "#1084D0"]');
  await expect(page.locator(".ed-style-error")).toHaveCount(0);
  await expect
    .poll(async () => {
      const text = await page.evaluate((key) => localStorage.getItem(key), STORAGE_KEY);
      return JSON.parse(text ?? "{}").init?.style?.header;
    }, { timeout: 3000 })
    .toEqual({ barStops: ["#000080", "#1084D0"] });
});
