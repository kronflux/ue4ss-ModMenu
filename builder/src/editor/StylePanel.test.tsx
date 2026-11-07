import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { emptyDocument } from "../schema";
import { FIELDS } from "../theme/fields.generated";
import { PRESET_ORDER } from "../theme/presets.generated";
import { StylePanel } from "./StylePanel";

describe("StylePanel", () => {
  it.each(["slate", "light", ...PRESET_ORDER.slice(0, 3)])("lists the scroll fields for %s, which resolves no scroll type", (theme) => {
    const document = emptyDocument();
    document.init.theme = theme;
    const html = renderToStaticMarkup(<StylePanel document={document} onPatchInit={() => {}} openTypes={["scroll"]} />);
    for (const field of Object.keys(FIELDS.types.scroll)) {
      expect(html, `${theme} scroll.${field}`).toContain(`scroll.${field}`);
    }
  });
});
