// Parsing of the JSON text editor for compound style fields, kept apart from the component so a test can run it.
import type { StyleIssue } from "../theme/resolve";

export type Parsed = { ok: true; value: unknown } | { ok: false; message?: string };

// The kinds whose JSON value is checked with the library validator, so the editor words a bad value
// as the validator does and never stores it.
export const CHECKED_KINDS = ["stops", "bevel", "faces", "xpface", "frame", "statusbar"];

export function parseJson(allowFalse: boolean, check?: (value: unknown) => StyleIssue[]) {
  return (text: string): Parsed => {
    if (text.trim() === "") {
      return { ok: true, value: undefined };
    }
    try {
      const value: unknown = JSON.parse(text);
      if ((allowFalse && value === false) || (typeof value === "object" && value !== null)) {
        const issue = check?.(value)[0];
        return issue === undefined ? { ok: true, value } : { ok: false, message: `${issue.path}: ${issue.message}` };
      }
    } catch {
      // Not JSON yet; keep the draft.
    }
    return { ok: false };
  };
}
