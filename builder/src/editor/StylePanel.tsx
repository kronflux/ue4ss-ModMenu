// The Theme panel and the item Look editor. Both show the resolved value of every field and write only
// the differences, through the style setters in model.ts.
import { useState } from "react";
import type { ReactNode } from "react";
import type { Item, MenuDocument } from "../schema";
import { FIELDS } from "../theme/fields.generated";
import { PRESETS, PRESET_ORDER } from "../theme/presets.generated";
import { OBJECT_TYPES, forItem, resolve } from "../theme/resolve";
import type { ResolvedEntry, ResolvedStyle } from "../theme/resolve";
import type { NodeRef } from "./model";
import {
  getItem,
  lookTypeOf,
  resetItemLook,
  resetStyleField,
  resolveDocument,
  setItemLook,
  setStyleBorrow,
  setStyleField,
  styleEntry,
} from "./model";

type ItemRef = Extract<NodeRef, { kind: "item" }>;
type Parsed = { ok: true; value: unknown } | { ok: false };

// ---------------------------------------------------------------------------------------------
// Colours: the resolved style is linear, the editor shows sRGB hex
// ---------------------------------------------------------------------------------------------

const HEX = /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;

function srgbByte(c: number): number {
  const v = c <= 0.0031308 ? c * 12.92 : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
  return Math.round(Math.min(1, Math.max(0, v)) * 255);
}

function byteHex(n: number): string {
  return n.toString(16).padStart(2, "0").toUpperCase();
}

// A hex string as stored, or a linear { R, G, B, A } table converted to "#RRGGBBAA".
function hexOf(value: unknown): string {
  if (typeof value === "string" && HEX.test(value)) {
    return value.toUpperCase();
  }
  if (typeof value === "object" && value !== null && "R" in value) {
    const c = value as { R: number; G: number; B: number; A?: number };
    const a = Math.round(Math.min(1, Math.max(0, c.A ?? 1)) * 255);
    return `#${byteHex(srgbByte(c.R))}${byteHex(srgbByte(c.G))}${byteHex(srgbByte(c.B))}${a === 255 ? "" : byteHex(a)}`;
  }
  return "";
}

function withAlpha(rgb: string, alpha: number): string {
  const a = Math.round(Math.min(1, Math.max(0, alpha)) * 255);
  return `${rgb.slice(0, 7).toUpperCase()}${a === 255 ? "" : byteHex(a)}`;
}

function alphaOf(hex: string): number {
  return hex.length === 9 ? parseInt(hex.slice(7, 9), 16) / 255 : 1;
}

// ---------------------------------------------------------------------------------------------
// Inputs
// ---------------------------------------------------------------------------------------------

// A text input that keeps what is typed while it has focus and writes each value that parses, so a
// half-typed value is never written and never snaps back under the cursor.
function DraftInput({
  label,
  value,
  parse,
  onCommit,
  multiline,
  placeholder,
}: {
  label: string;
  value: string;
  parse: (text: string) => Parsed;
  onCommit: (value: unknown) => void;
  multiline?: boolean;
  placeholder?: string;
}) {
  const [draft, setDraft] = useState<string | null>(null);
  const change = (text: string) => {
    setDraft(text);
    const parsed = parse(text);
    if (parsed.ok) {
      onCommit(parsed.value);
    }
  };
  const bad = draft !== null && !parse(draft).ok;
  const common = {
    "aria-label": label,
    "aria-invalid": bad || undefined,
    value: draft ?? value,
    placeholder,
    onBlur: () => setDraft(null),
  };
  return multiline ? (
    <textarea rows={3} {...common} onChange={(event) => change(event.target.value)} />
  ) : (
    <input type="text" {...common} onChange={(event) => change(event.target.value)} />
  );
}

const parseNumber = (text: string): Parsed => {
  if (text.trim() === "") {
    return { ok: true, value: undefined };
  }
  const n = Number(text);
  return Number.isFinite(n) ? { ok: true, value: n } : { ok: false };
};

// A radius is one number, or four in top left, top right, bottom right, bottom left order.
const parseRadius = (text: string): Parsed => {
  if (text.trim() === "") {
    return { ok: true, value: undefined };
  }
  const parts = text.split(",").map((part) => Number(part.trim()));
  if (parts.some((n) => !Number.isFinite(n)) || (parts.length !== 1 && parts.length !== 4)) {
    return { ok: false };
  }
  return { ok: true, value: parts.length === 1 ? parts[0] : parts };
};

// A font chain is a list of font ids, tried in order.
const parseFont = (text: string): Parsed => {
  const ids = text.split(",").map((part) => part.trim()).filter((part) => part !== "");
  if (ids.length === 0) {
    return { ok: true, value: undefined };
  }
  return { ok: true, value: ids.length === 1 ? ids[0] : ids };
};

function parseJson(allowFalse: boolean) {
  return (text: string): Parsed => {
    if (text.trim() === "") {
      return { ok: true, value: undefined };
    }
    try {
      const value: unknown = JSON.parse(text);
      if ((allowFalse && value === false) || (typeof value === "object" && value !== null)) {
        return { ok: true, value };
      }
    } catch {
      // Not JSON yet; keep the draft.
    }
    return { ok: false };
  };
}

const parseHex = (text: string): Parsed => {
  const trimmed = text.trim();
  if (trimmed === "") {
    return { ok: true, value: undefined };
  }
  return HEX.test(trimmed) ? { ok: true, value: trimmed } : { ok: false };
};

function listText(value: unknown): string {
  if (Array.isArray(value)) {
    return value.join(", ");
  }
  return value === undefined || value === null ? "" : String(value);
}

// ---------------------------------------------------------------------------------------------
// One field
// ---------------------------------------------------------------------------------------------

function FieldEditor({
  name,
  label,
  kind,
  current,
  stored,
  onSet,
}: {
  name: string;
  label: string;
  kind: string;
  current: unknown;
  stored: unknown;
  onSet: (value: unknown) => void;
}) {
  const changed = stored !== undefined;
  let control;
  if (kind === "color") {
    const hex = hexOf(changed ? stored : current);
    control = (
      <span className="ed-style-color">
        <input
          type="color"
          aria-label={`${label} swatch`}
          value={(hex || "#000000").slice(0, 7).toLowerCase()}
          onChange={(event) => onSet(withAlpha(event.target.value, alphaOf(hex)))}
        />
        <DraftInput label={label} value={hex} parse={parseHex} onCommit={onSet} />
        <DraftInput
          label={`${label} alpha`}
          value={hex ? String(Math.round(alphaOf(hex) * 100) / 100) : ""}
          parse={(text) => {
            const n = Number(text);
            return text.trim() !== "" && Number.isFinite(n) && n >= 0 && n <= 1 ? { ok: true, value: n } : { ok: false };
          }}
          onCommit={(a) => onSet(withAlpha(hex || "#000000", a as number))}
        />
      </span>
    );
  } else if (kind === "boolean") {
    control = <input type="checkbox" aria-label={label} checked={current === true} onChange={(event) => onSet(event.target.checked)} />;
  } else if (kind.startsWith("enum:")) {
    const options = kind.slice(5).split("|");
    const value = typeof current === "string" ? current : "";
    control = (
      <select aria-label={label} value={value} onChange={(event) => onSet(event.target.value === "" ? undefined : event.target.value)}>
        {!options.includes(value) && <option value={value}>{value === "" ? "not set" : value}</option>}
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    );
  } else if (kind === "number") {
    control = <DraftInput label={label} value={typeof current === "number" ? String(current) : ""} parse={parseNumber} onCommit={onSet} />;
  } else if (kind === "radius") {
    control = <DraftInput label={label} value={listText(current)} parse={parseRadius} onCommit={onSet} placeholder="4, or 4, 4, 0, 0" />;
  } else if (kind === "font") {
    control = <DraftInput label={label} value={listText(current)} parse={parseFont} onCommit={onSet} placeholder="kanit, roboto" />;
  } else if (kind === "string") {
    control = <DraftInput label={label} value={typeof current === "string" ? current : ""} parse={(text) => ({ ok: true, value: text })} onCommit={onSet} />;
  } else {
    // text, roles, shadow and table hold nested values, edited as JSON. Only the stored difference is
    // shown, because the resolved value holds linear colours that would be written back as tables.
    control = (
      <DraftInput
        label={label}
        multiline
        value={changed ? JSON.stringify(stored) : ""}
        parse={parseJson(kind === "shadow")}
        onCommit={onSet}
        placeholder="Preset value. Write JSON to change it."
      />
    );
  }
  return (
    <div className={changed ? "ed-style-field is-changed" : "ed-style-field"}>
      <span className="ed-style-name" title={kind}>
        {name}
      </span>
      {control}
      {changed && (
        <button type="button" aria-label={`Reset ${label}`} onClick={() => onSet(undefined)}>
          Reset
        </button>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------------------------
// The Theme panel
// ---------------------------------------------------------------------------------------------

function presetName(id: string): string {
  const name = PRESETS[id]?.name;
  return typeof name === "string" ? name : id;
}

// The resolved style to show: the document's own, or the bare theme while the style has a bad value.
function shownStyle(doc: MenuDocument): { resolved: ResolvedStyle; ok: boolean } {
  const resolved = resolveDocument(doc);
  if (resolved !== null) {
    return { resolved, ok: true };
  }
  try {
    return { resolved: resolve(doc.init.theme), ok: false };
  } catch {
    return { resolved: resolve("light"), ok: false };
  }
}

export function StylePanel({
  document,
  onPatchInit,
}: {
  document: MenuDocument;
  onPatchInit: (patch: Partial<MenuDocument["init"]>) => void;
}) {
  const { resolved, ok } = shownStyle(document);
  const style = document.init.style;
  const apply = (next: MenuDocument) => onPatchInit({ style: next.init.style });
  const theme = document.init.theme;
  return (
    <div className="ed-style">
      <label className="ed-field">
        <span>Theme</span>
        <select aria-label="Theme" value={theme} onChange={(event) => onPatchInit({ theme: event.target.value })}>
          {!PRESET_ORDER.includes(theme) && <option value={theme}>{theme}</option>}
          {PRESET_ORDER.map((id) => (
            <option key={id} value={id}>
              {presetName(id)}
            </option>
          ))}
        </select>
      </label>
      <p className="ed-muted">The menu stores only what you change from the theme.</p>
      {!ok && <p className="ed-warn">The style has a value that does not resolve. The issues list names it.</p>}
      <Group
        type="palette"
        summary={
          <>
            palette <Changed count={Object.keys(styleEntry(style, "palette").fields).length} />
          </>
        }
      >
        {() => FIELDS.palette.map((key) => (
          <FieldEditor
            key={key}
            name={key}
            label={`palette.${key}`}
            kind="color"
            current={resolved.palette[key]}
            stored={styleEntry(style, "palette").fields[key]}
            onSet={(value) => apply(setStyleField(document, "palette", key, value))}
          />
        ))}
      </Group>
      {OBJECT_TYPES.map((type) => {
        const entry = styleEntry(style, type);
        const count = Object.keys(entry.fields).length + (entry.from === undefined ? 0 : 1);
        return (
          <Group
            key={type}
            type={type}
            summary={
              <>
                {type} <Changed count={count} />
              </>
            }
          >
            {() => (
              <>
            <div className="ed-style-field">
              <span className="ed-style-name">borrow from</span>
              <select
                aria-label={`${type} borrows from`}
                value={entry.from ?? ""}
                onChange={(event) => apply(setStyleBorrow(document, type, event.target.value === "" ? null : event.target.value))}
              >
                <option value="">none</option>
                {entry.from !== undefined && !PRESET_ORDER.includes(entry.from) && <option value={entry.from}>{entry.from}</option>}
                {PRESET_ORDER.map((id) => (
                  <option key={id} value={id}>
                    {presetName(id)}
                  </option>
                ))}
              </select>
            </div>
            {Object.entries(FIELDS.types[type]).map(([field, kind]) => (
              <FieldEditor
                key={field}
                name={field}
                label={`${type}.${field}`}
                kind={kind}
                current={resolved[type][field]}
                stored={entry.fields[field]}
                onSet={(value) =>
                  apply(value === undefined ? resetStyleField(document, type, field) : setStyleField(document, type, field, value))
                }
              />
            ))}
              </>
            )}
          </Group>
        );
      })}
    </div>
  );
}

// A collapsible group that builds its fields only while open, so a closed panel adds no inputs to the
// page: 19 types hold over 200 fields, and their labels would match other fields' label searches.
function Group({ type, summary, children }: { type: string; summary: ReactNode; children: () => ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <details className="ed-style-type" data-type={type} open={open} onToggle={(event) => setOpen(event.currentTarget.open)}>
      <summary>{summary}</summary>
      {open && children()}
    </details>
  );
}

function Changed({ count }: { count: number }) {
  return count > 0 ? <span className="ed-style-count">{count} changed</span> : null;
}

// ---------------------------------------------------------------------------------------------
// The item Look editor
// ---------------------------------------------------------------------------------------------

export function LookPanel({
  document,
  selection,
  item,
  onPatchItem,
}: {
  document: MenuDocument;
  selection: ItemRef;
  item: Item;
  onPatchItem: (patch: Record<string, unknown>) => void;
}) {
  const type = lookTypeOf(item);
  if (type === undefined) {
    return null;
  }
  const look = typeof item.look === "object" && item.look !== null ? item.look : {};
  const { resolved } = shownStyle(document);
  let current: ResolvedEntry;
  try {
    current = forItem(resolved, type, look);
  } catch {
    current = resolved[type as keyof ResolvedStyle] as ResolvedEntry;
  }
  // The setter returns a whole document; the item's new look is all this panel writes.
  const apply = (next: MenuDocument) => onPatchItem({ look: getItem(next, selection)?.look });
  const count = Object.keys(look).length;
  return (
    <Group
      type="look"
      summary={
        <>
          Look ({type}) <Changed count={count} />
        </>
      }
    >
      {() => (
        <>
      <p className="ed-muted">Changes this item only, over the theme's {type} style.</p>
      {Object.entries(FIELDS.types[type] ?? {}).map(([field, kind]) => (
        <FieldEditor
          key={field}
          name={field}
          label={`look.${field}`}
          kind={kind}
          current={current[field]}
          stored={look[field]}
          onSet={(value) =>
            apply(value === undefined ? resetItemLook(document, selection, field) : setItemLook(document, selection, field, value))
          }
        />
      ))}
        </>
      )}
    </Group>
  );
}
