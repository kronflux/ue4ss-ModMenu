import { describe, expect, it } from "vitest";
import { parseJson } from "./jsonField";
import { setStyleField } from "./model";
import { emptyDocument } from "../schema";
import { styleIssues } from "../theme/resolve";

// A partial value is valid, because no key inside a compound kind is required.
describe("the JSON field editor", () => {
  const check = (value: unknown) => styleIssues({ toggle: { checkBevel: value } }, "toggle");

  it("accepts a bevel with only a width, with no message, and stores it", () => {
    const parsed = parseJson(false, check)('{ "width": 2 }');
    expect(parsed).toEqual({ ok: true, value: { width: 2 } });
    const doc = setStyleField(emptyDocument(), "toggle", "checkBevel", { width: 2 });
    expect(doc.init.style).toEqual({ toggle: { checkBevel: { width: 2 } } });
  });

  it("rejects a bevel colour that is not a colour, with the validator's message", () => {
    const parsed = parseJson(false, check)('{ "light": 5 }');
    expect(parsed.ok).toBe(false);
    expect(!parsed.ok && parsed.message).toContain("light");
  });
});
