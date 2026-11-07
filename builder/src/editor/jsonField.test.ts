import { describe, expect, it } from "vitest";
import { CHECKED_KINDS, parseJson } from "./jsonField";
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

  it("checks an arrowbutton with the validator, so a one-colour face gets the stops error", () => {
    expect(CHECKED_KINDS).toContain("arrowbutton");
    const arrow = (value: unknown) => styleIssues({ field: { arrow: value } }, "field");
    const parsed = parseJson(false, arrow)('{"face":["#fff"]}');
    expect(parsed.ok).toBe(false);
    expect(!parsed.ok && parsed.message).toContain("face");
    expect(!parsed.ok && parsed.message).toContain(arrow({ face: ["#fff"] })[0]!.message);
    expect(parseJson(false, arrow)('{"face":["#000000","#FFFFFF"],"size":16}').ok).toBe(true);
  });

  it("rejects a bevel colour that is not a colour, with the validator's message", () => {
    const parsed = parseJson(false, check)('{ "light": 5 }');
    expect(parsed.ok).toBe(false);
    expect(!parsed.ok && parsed.message).toContain("light");
  });
});
