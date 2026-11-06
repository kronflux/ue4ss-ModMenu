/**
 * Generate the Lua and TypeScript copies of the theme field list and the preset files.
 *
 * Usage:
 *   node tools/gen-themes.mjs           write every output that differs from the JSON
 *   node tools/gen-themes.mjs --check   write nothing; exit 1 and name each stale output
 *
 * Any other argument prints the usage and exits 2 without writing.
 *
 * Source: themes/fields.json and themes/presets/<id>.json.
 * Outputs: core/stylefields.lua, core/presets.lua, builder/src/theme/fields.generated.ts and
 * builder/src/theme/presets.generated.ts.
 *
 * The JSON is the one source. The library and the builder each read their generated copy, so the
 * two cannot drift apart without --check reporting it.
 */

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const COMMAND = "node tools/gen-themes.mjs";

export const OUTPUTS = [
  "core/stylefields.lua",
  "core/presets.lua",
  "builder/src/theme/fields.generated.ts",
  "builder/src/theme/presets.generated.ts",
];

// Every preset id in the order ModMenu.Themes() lists them: the two legacy themes, then the
// stage 1 list from the spec, then the stage 2 list. Only ids that have a file are generated. A
// file whose id is missing here fails, so a new preset is placed in the order on purpose.
const PRESET_ORDER = [
  "light",
  "dark",
  "slate",
  "glass",
  "storm",
  "neon",
  "doppler",
  "tornado-warning",
  "night-drive",
  "loadout",
  "cozy",
  "carbon",
  "blueprint",
  "paper-blue",
  "field-kit",
  "ink",
  "aurora",
  "midnight",
  "storm-front",
  "sakura",
  "ocean",
  "steel",
  "paper-sage",
  "dracula",
  "catppuccin-mocha",
  "catppuccin-latte",
  "material",
  "monokai",
  "nord",
  "terminal",
  "hologram",
  "frost",
  "win11-light",
  "win11-dark",
  "mac-light",
  "mac-dark",
  "xp-luna",
  "xp-royale-noir",
  "windows-classic",
];

const KINDS = new Set([
  "color", "number", "boolean", "string", "radius", "font", "text", "roles", "shadow", "table",
  "stops", "bevel", "faces", "xpface", "frame", "statusbar",
]);

// The roles a button style may colour, and the keys each role takes. A role may also name its own
// button variant, because StyleLab themes such as Carbon draw one role as a fill and another as an
// underline.
const ROLE_NAMES = ["default", "primary", "secondary", "success", "danger", "warning", "info", "active", "disabled"];
const ROLE_KEYS = { fill: "color", text: "color", hover: "color", pressed: "color", edge: "color", variant: null };

const SHADOW_KEYS = { x: "number", y: "number", color: "color" };

// The keys of the stage 2 kinds that are a fixed set of fields. A key may itself hold one of these
// kinds, such as an xp face holding two `stops` lists. Every key is optional, so a borrowed value
// that kept only a width is still valid.
const FIXED_KINDS = {
  bevel: { light: "color", dark: "color", innerLight: "color", innerDark: "color", width: "number" },
  xpface: { edge: "color", glow: "color", defaultRing: "color", face: "stops", pressedFace: "stops" },
  frame: { edge: "color", fill: "color", radius: "radius", pad: "number", bevel: "bevel" },
  statusbar: { text: "string", fill: "color", line: "color" },
};
const FACE_KEYS = { fill: "color", text: "color" };

// Keys a preset file may hold beside its object types.
const META_KEYS = new Set(["id", "stage", "name", "subtitle", "footer", "palette", "base", "parts"]);

const ID_RE = /^[a-z0-9-]+$/;
const HEX_RE = /^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/;
const LUA_NAME_RE = /^[A-Za-z_][A-Za-z0-9_]*$/;
const LUA_KEYWORDS = new Set([
  "and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while",
]);
const TS_NAME_RE = /^[A-Za-z_$][A-Za-z0-9_$]*$/;

/** Read and parse a JSON file, naming the file when the JSON is malformed. */
function readJson(abs, label) {
  let text;
  try {
    text = fs.readFileSync(abs, "utf8");
    if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
  } catch (err) {
    throw new Error(`${label}: cannot be read (${err.message})`);
  }
  try {
    return JSON.parse(text);
  } catch (err) {
    throw new Error(`${label}: is not valid JSON (${err.message})`);
  }
}

function isObject(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v);
}

// A table of keys. An empty list counts as an empty table, because Lua cannot tell the two apart,
// but a list with entries is not one.
function isKeyTable(v) {
  return isObject(v) || (Array.isArray(v) && v.length === 0);
}

/** Check the field list itself, so a typo in a kind fails here and not in every preset. */
function validateFields(fields) {
  const where = "themes/fields.json";
  if (!isObject(fields) || fields.version !== 1) {
    throw new Error(`${where}: version must be 1`);
  }
  if (!Array.isArray(fields.palette) || fields.palette.some((k) => typeof k !== "string")) {
    throw new Error(`${where}: palette must be a list of colour names`);
  }
  if (!isObject(fields.types)) {
    throw new Error(`${where}: types must be a table of object types`);
  }
  for (const [type, entries] of Object.entries(fields.types)) {
    if (!isObject(entries)) {
      throw new Error(`${where}: ${type} must be a table of fields`);
    }
    for (const [field, kind] of Object.entries(entries)) {
      const ok = typeof kind === "string" && (KINDS.has(kind) || /^enum:[^|]+(\|[^|]+)*$/.test(kind));
      if (!ok) {
        throw new Error(`${where}: ${type}.${field} has an unknown kind ${JSON.stringify(kind)}`);
      }
    }
  }
  if (!isObject(fields.types.title)) {
    throw new Error(`${where}: the title type is required, because text style tables take its fields`);
  }
}

function isColor(v) {
  if (typeof v === "string") {
    return HEX_RE.test(v);
  }
  if (!isObject(v)) {
    return false;
  }
  const keys = Object.keys(v);
  if (keys.some((k) => !["R", "G", "B", "A"].includes(k))) {
    return false;
  }
  return ["R", "G", "B"].every((k) => Number.isFinite(v[k])) && (v.A === undefined || Number.isFinite(v.A));
}

function describeKind(kind) {
  switch (kind) {
    case "color":
      return 'a colour ("#RRGGBB", "#RRGGBBAA" or { R, G, B, A })';
    case "radius":
      return "a number or a list of 4 numbers";
    case "font":
      return "a font id or a list of font ids";
    case "text":
      return "a text style table";
    case "roles":
      return "a table of button roles";
    case "shadow":
      return "a shadow table { x, y, color }";
    case "stops":
      return "a list of at least 2 colours";
    case "bevel":
      return "a bevel table { light, dark, innerLight, innerDark, width }";
    case "faces":
      return "a table of button roles, each { fill, text }";
    case "xpface":
      return "an xp face table { edge, glow, defaultRing, face, pressedFace }";
    case "frame":
      return "a frame table { edge, fill, radius, pad, bevel }";
    case "statusbar":
      return "a status bar table { text, fill, line }";
    case "table":
      return "a table or a list";
    default:
      if (kind.startsWith("enum:")) {
        return `one of ${kind.slice(5).split("|").join(", ")}`;
      }
      return `a ${kind}`;
  }
}

/**
 * Check one value against its kind. `where` is the file label and `name` the dotted field path,
 * so every error names both. `ctx.textFields` holds the fields a text style table takes, and
 * `ctx.roleVariant` the kind of a button role's own variant.
 */
function validateValue(kind, value, where, name, ctx) {
  const fail = () => {
    throw new Error(`${where}: ${name} must be ${describeKind(kind)}`);
  };
  if (kind.startsWith("enum:")) {
    if (!kind.slice(5).split("|").includes(value)) fail();
    return;
  }
  switch (kind) {
    case "color":
      if (!isColor(value)) fail();
      return;
    case "number":
      if (!Number.isFinite(value)) fail();
      return;
    case "boolean":
      if (typeof value !== "boolean") fail();
      return;
    case "string":
      if (typeof value !== "string") fail();
      return;
    case "radius":
      if (Number.isFinite(value)) return;
      if (!Array.isArray(value) || value.length !== 4 || !value.every(Number.isFinite)) fail();
      return;
    case "font":
      if (typeof value === "string" && value !== "") return;
      if (!Array.isArray(value) || value.length === 0 || !value.every((f) => typeof f === "string" && f !== "")) fail();
      return;
    case "table":
      if (value === null || typeof value !== "object") fail();
      return;
    case "shadow":
      if (!isObject(value)) fail();
      for (const [key, sub] of Object.entries(value)) {
        if (!Object.hasOwn(SHADOW_KEYS, key)) {
          throw new Error(`${where}: ${name}.${key} is not a known field`);
        }
        validateValue(SHADOW_KEYS[key], sub, where, `${name}.${key}`, ctx);
      }
      return;
    case "stops":
      if (!Array.isArray(value) || value.length < 2) fail();
      value.forEach((stop, i) => validateValue("color", stop, where, `${name}[${i + 1}]`, ctx));
      return;
    case "bevel":
    case "xpface":
    case "frame":
    case "statusbar":
      if (!isKeyTable(value)) fail();
      for (const [key, sub] of Object.entries(value)) {
        if (!Object.hasOwn(FIXED_KINDS[kind], key)) {
          throw new Error(`${where}: ${name}.${key} is not a known field`);
        }
        validateValue(FIXED_KINDS[kind][key], sub, where, `${name}.${key}`, ctx);
      }
      return;
    case "faces":
      if (!isKeyTable(value)) fail();
      for (const [role, entry] of Object.entries(value)) {
        if (!ROLE_NAMES.includes(role)) {
          throw new Error(`${where}: ${name}.${role} is not a known role (${ROLE_NAMES.join(", ")})`);
        }
        if (!isKeyTable(entry)) {
          throw new Error(`${where}: ${name}.${role} must be a table of face colours`);
        }
        for (const [key, sub] of Object.entries(entry)) {
          if (!Object.hasOwn(FACE_KEYS, key)) {
            throw new Error(`${where}: ${name}.${role}.${key} is not a known field`);
          }
          validateValue(FACE_KEYS[key], sub, where, `${name}.${role}.${key}`, ctx);
        }
      }
      return;
    case "text":
      if (!isObject(value)) fail();
      for (const [key, sub] of Object.entries(value)) {
        if (!Object.hasOwn(ctx.textFields, key)) {
          throw new Error(`${where}: ${name}.${key} is not a known field`);
        }
        validateValue(ctx.textFields[key], sub, where, `${name}.${key}`, ctx);
      }
      return;
    case "roles":
      if (!isObject(value)) fail();
      for (const [role, entry] of Object.entries(value)) {
        if (!ROLE_NAMES.includes(role)) {
          throw new Error(`${where}: ${name}.${role} is not a known role (${ROLE_NAMES.join(", ")})`);
        }
        if (!isObject(entry)) {
          throw new Error(`${where}: ${name}.${role} must be a table of role colours`);
        }
        for (const [key, sub] of Object.entries(entry)) {
          if (!Object.hasOwn(ROLE_KEYS, key)) {
            throw new Error(`${where}: ${name}.${role}.${key} is not a known field`);
          }
          const subKind = ROLE_KEYS[key] ?? ctx.roleVariant;
          validateValue(subKind, sub, where, `${name}.${role}.${key}`, ctx);
        }
      }
      return;
    default:
      throw new Error(`${where}: ${name} has an unknown kind ${kind}`);
  }
}

/** Check one preset against the field list. `ids` is the set of every preset id, for base and parts. */
function validatePreset(preset, file, fields, ids) {
  const where = `themes/presets/${file}`;
  const expected = path.basename(file, ".json");
  if (!isObject(preset)) {
    throw new Error(`${where}: must be a JSON object`);
  }
  if (typeof preset.id !== "string" || !ID_RE.test(preset.id)) {
    throw new Error(`${where}: id must be lowercase letters, digits and hyphens`);
  }
  if (preset.id !== expected) {
    throw new Error(`${where}: id "${preset.id}" must equal the file name "${expected}"`);
  }
  if (!PRESET_ORDER.includes(preset.id)) {
    throw new Error(`${where}: id "${preset.id}" is not in the preset order list in tools/gen-themes.mjs`);
  }
  if (preset.stage !== 1 && preset.stage !== 2) {
    throw new Error(`${where}: stage must be 1 or 2`);
  }
  for (const key of ["name", "subtitle", "footer"]) {
    if (preset[key] !== undefined && typeof preset[key] !== "string") {
      throw new Error(`${where}: ${key} must be a string`);
    }
  }
  // Text style tables take the title type's fields. A button role's own variant takes the values of
  // button.variant.
  const ctx = {
    textFields: fields.types.title,
    roleVariant: fields.types.button?.variant ?? "enum:fill|soft|ghost|underline",
  };
  if (preset.palette !== undefined) {
    if (!isObject(preset.palette)) {
      throw new Error(`${where}: palette must be a table of colours`);
    }
    for (const [key, value] of Object.entries(preset.palette)) {
      if (!fields.palette.includes(key)) {
        throw new Error(`${where}: palette.${key} is not a known palette colour`);
      }
      validateValue("color", value, where, `palette.${key}`, ctx);
    }
  }
  if (preset.base !== undefined && (typeof preset.base !== "string" || !ids.has(preset.base))) {
    throw new Error(`${where}: base must name a preset that has a file`);
  }
  if (preset.parts !== undefined) {
    if (!isObject(preset.parts)) {
      throw new Error(`${where}: parts must be a table of object type to preset id`);
    }
    for (const [type, id] of Object.entries(preset.parts)) {
      if (!Object.hasOwn(fields.types, type)) {
        throw new Error(`${where}: parts.${type} is not a known object type`);
      }
      if (typeof id !== "string" || !ids.has(id)) {
        throw new Error(`${where}: parts.${type} must name a preset that has a file`);
      }
    }
  }
  for (const [type, entry] of Object.entries(preset)) {
    if (META_KEYS.has(type)) continue;
    const known = Object.hasOwn(fields.types, type) ? fields.types[type] : undefined;
    if (known === undefined) {
      throw new Error(`${where}: unknown object type ${type}`);
    }
    if (!isObject(entry)) {
      throw new Error(`${where}: ${type} must be a table of fields`);
    }
    for (const [field, value] of Object.entries(entry)) {
      if (!Object.hasOwn(known, field)) {
        throw new Error(`${where}: ${type}.${field} is not a known field`);
      }
      validateValue(known[field], value, where, `${type}.${field}`, ctx);
      const elements = TABLE_ELEMENTS[`${type}.${field}`];
      if (elements !== undefined) {
        elements(value, where, `${type}.${field}`);
      }
    }
  }
  assertPrintable(preset, where, "");
}

// Element checks for the free-form `table` fields, ramp and shadowLayers. The stage 2 fields have
// their own kinds and are checked by validateValue.
const TABLE_ELEMENTS = {
  "progress.ramp": (value, where, name) => {
    if (!Array.isArray(value) || value.length === 0) {
      throw new Error(`${where}: ${name} must be a list of colours`);
    }
    value.forEach((c, i) => {
      if (!isColor(c)) {
        throw new Error(`${where}: ${name}[${i + 1}] must be ${describeKind("color")}`);
      }
    });
  },
  "panel.shadowLayers": (value, where, name) => {
    if (!Array.isArray(value) || value.length === 0) {
      throw new Error(`${where}: ${name} must be a list of [alpha, depth] pairs`);
    }
    value.forEach((layer, i) => {
      if (!Array.isArray(layer) || layer.length !== 2 || !layer.every(Number.isFinite)) {
        throw new Error(`${where}: ${name}[${i + 1}] must be two numbers, [alpha, depth]`);
      }
    });
  },
};

/**
 * Check that every value in a preset can be written as Lua and TypeScript. JSON can hold null,
 * which neither output can carry, so a null anywhere fails here with the file and field named.
 */
function assertPrintable(value, where, name) {
  if (value === null) {
    throw new Error(`${where}: ${name || "the preset"} is null, which cannot be written; leave the field out instead`);
  }
  if (typeof value !== "object") return;
  if (Array.isArray(value)) {
    value.forEach((v, i) => assertPrintable(v, where, `${name}[${i + 1}]`));
    return;
  }
  for (const [k, v] of Object.entries(value)) {
    assertPrintable(v, where, name ? `${name}.${k}` : k);
  }
}

/** Load and check the field list and every preset. Presets come back in PRESET_ORDER. */
function load(root) {
  const fields = readJson(path.join(root, "themes", "fields.json"), "themes/fields.json");
  validateFields(fields);

  const dir = path.join(root, "themes", "presets");
  const files = fs
    .readdirSync(dir, { withFileTypes: true })
    .filter((ent) => ent.isFile() && ent.name.endsWith(".json"))
    .map((ent) => ent.name)
    .sort();
  const ids = new Set(files.map((f) => path.basename(f, ".json")));
  const byId = new Map();
  for (const file of files) {
    const preset = readJson(path.join(dir, file), `themes/presets/${file}`);
    validatePreset(preset, file, fields, ids);
    byId.set(preset.id, preset);
  }
  const order = PRESET_ORDER.filter((id) => byId.has(id));
  return { fields, order, presets: order.map((id) => byId.get(id)) };
}

// ------------------------------------------------------------------------------------------
// Writers. One small printer serves Lua and TypeScript: a table whose values hold no table, and
// whose one-line form fits, is written on one line; anything else is written one entry a line.
// ------------------------------------------------------------------------------------------

const MAX_INLINE = 100;

function luaString(s) {
  let out = '"';
  for (const ch of s) {
    const code = ch.codePointAt(0);
    if (ch === '"') out += '\\"';
    else if (ch === "\\") out += "\\\\";
    else if (ch === "\n") out += "\\n";
    else if (ch === "\r") out += "\\r";
    else if (ch === "\t") out += "\\t";
    else if (code < 32 || code === 127) out += "\\" + String(code).padStart(3, "0");
    else out += ch;
  }
  return out + '"';
}

function luaNumber(n) {
  // JSON numbers print the same in Lua, including exponents such as 1e-7.
  return String(n);
}

const LUA = {
  scalar(v) {
    if (typeof v === "string") return luaString(v);
    if (typeof v === "number") return luaNumber(v);
    if (typeof v === "boolean") return v ? "true" : "false";
    throw new Error(`cannot write ${JSON.stringify(v)} as Lua`);
  },
  key(k) {
    return LUA_NAME_RE.test(k) && !LUA_KEYWORDS.has(k) ? `${k} = ` : `[${luaString(k)}] = `;
  },
  open: "{",
  close: "}",
  arrayOpen: "{",
  arrayClose: "}",
  indent: "    ",
};

const TS = {
  scalar(v) {
    if (typeof v === "string" || typeof v === "number" || typeof v === "boolean") return JSON.stringify(v);
    throw new Error(`cannot write ${JSON.stringify(v)} as TypeScript`);
  },
  key(k) {
    return TS_NAME_RE.test(k) ? `${k}: ` : `${JSON.stringify(k)}: `;
  },
  open: "{",
  close: "}",
  arrayOpen: "[",
  arrayClose: "]",
  indent: "  ",
};

/**
 * Print a value. `at` names the value for an error: its source file and dotted field path. The
 * preset checks already reject every value the printer cannot write, so an error here means a
 * check is missing.
 */
function print(value, syntax, depth, at) {
  if (value === null || typeof value !== "object") {
    try {
      return syntax.scalar(value);
    } catch (err) {
      throw new Error(`${at.file}: ${at.name || "the value"}: ${err.message}`);
    }
  }
  const isArray = Array.isArray(value);
  const entries = isArray ? value.map((v) => [null, v]) : Object.entries(value);
  const open = isArray ? syntax.arrayOpen : syntax.open;
  const close = isArray ? syntax.arrayClose : syntax.close;
  if (entries.length === 0) {
    return `${open}${close}`;
  }
  const child = (k, i) => {
    if (at.children && k !== null && Object.hasOwn(at.children, k)) return at.children[k];
    if (at.fileOf && k !== null) return { file: at.fileOf(k), name: "" };
    const step = k === null ? `[${i + 1}]` : at.name ? `.${k}` : k;
    return { file: at.file, name: at.name + step };
  };
  const flat = entries.every(([, v]) => v === null || typeof v !== "object");
  if (flat) {
    const parts = entries.map(([k, v], i) => (k === null ? "" : syntax.key(k)) + print(v, syntax, depth + 1, child(k, i)));
    const line = `${open} ${parts.join(", ")} ${close}`;
    if (line.length + depth * syntax.indent.length <= MAX_INLINE) {
      return line;
    }
  }
  const pad = syntax.indent.repeat(depth + 1);
  const lines = entries.map(
    ([k, v], i) => pad + (k === null ? "" : syntax.key(k)) + print(v, syntax, depth + 1, child(k, i)) + ",",
  );
  return `${open}\n${lines.join("\n")}\n${syntax.indent.repeat(depth)}${close}`;
}

// Where-labels for the printer. A preset map's keys are preset ids, so each child is named by
// its own file.
const FIELDS_AT = { file: "themes/fields.json", name: "" };
const PRESET_MAP_AT = { file: "themes/presets", name: "", fileOf: (id) => `themes/presets/${id}.json` };

function luaHeader(what) {
  return [
    `-- Generated by ${COMMAND} from ${what}. Do not edit this file; edit the JSON and run the command again.`,
    "",
  ].join("\n");
}

function tsHeader(what) {
  return [
    `// Generated by ${COMMAND} from ${what}. Do not edit this file; edit the JSON and run the command again.`,
    "",
  ].join("\n");
}

function stylefieldsLua(fields) {
  const data = { version: fields.version, palette: fields.palette, types: fields.types };
  return `${luaHeader("themes/fields.json")}\nreturn ${print(data, LUA, 0, FIELDS_AT)}\n`;
}

function presetsLua(order, presets) {
  const map = {};
  for (const preset of presets) map[preset.id] = preset;
  const data = { order, presets: map };
  const at = { file: "themes/presets", name: "", children: { presets: PRESET_MAP_AT } };
  return `${luaHeader("themes/presets/*.json")}\nreturn ${print(data, LUA, 0, at)}\n`;
}

function fieldsTs(fields) {
  const data = { version: fields.version, palette: fields.palette, types: fields.types };
  return [
    tsHeader("themes/fields.json"),
    "/** The field list: palette colour names, and each object type's fields with their kinds. */",
    "export interface FieldList {",
    "  readonly version: number;",
    "  readonly palette: readonly string[];",
    "  readonly types: Readonly<Record<string, Readonly<Record<string, string>>>>;",
    "}",
    "",
    `export const FIELDS: FieldList = ${print(data, TS, 0, FIELDS_AT)};`,
    "",
  ].join("\n");
}

function presetsTs(order, presets) {
  const map = {};
  for (const preset of presets) map[preset.id] = preset;
  return [
    tsHeader("themes/presets/*.json"),
    "/** A preset as written in its JSON file: colours are hex strings or linear { R, G, B, A } tables. */",
    "export interface PresetDefinition {",
    "  readonly id: string;",
    "  readonly stage: number;",
    "  readonly [key: string]: unknown;",
    "}",
    "",
    `export const PRESET_ORDER: readonly string[] = ${print(order, TS, 0, { file: "themes/presets", name: "order" })};`,
    "",
    `export const PRESETS: Readonly<Record<string, PresetDefinition>> = ${print(map, TS, 0, PRESET_MAP_AT)};`,
    "",
  ].join("\n");
}

/**
 * Build every output from the JSON under `root`.
 * @param {string} root the repository root, or a copy of it that holds themes/
 * @returns {Map<string, string>} relative output path to file text
 */
export function generate(root) {
  const { fields, order, presets } = load(root);
  return new Map([
    ["core/stylefields.lua", stylefieldsLua(fields)],
    ["core/presets.lua", presetsLua(order, presets)],
    ["builder/src/theme/fields.generated.ts", fieldsTs(fields)],
    ["builder/src/theme/presets.generated.ts", presetsTs(order, presets)],
  ]);
}

/** Read an output, with line endings made LF, so a checkout that writes CRLF is not stale. */
function readOutput(root, rel) {
  const abs = path.join(root, rel);
  if (!fs.existsSync(abs)) return null;
  return fs.readFileSync(abs, "utf8").replace(/\r\n/g, "\n");
}

/**
 * List the outputs under `root` that are missing or differ from what the JSON generates.
 * Writes nothing.
 * @param {string} root
 * @returns {string[]} relative paths of stale outputs, in OUTPUTS order
 */
export function check(root) {
  const files = generate(root);
  return OUTPUTS.filter((rel) => readOutput(root, rel) !== files.get(rel));
}

/**
 * Write every output under `root` that differs from what the JSON generates.
 * @param {string} root
 * @returns {string[]} relative paths written
 */
export function write(root) {
  const files = generate(root);
  const written = [];
  for (const rel of OUTPUTS) {
    const text = files.get(rel);
    if (readOutput(root, rel) === text) continue;
    const abs = path.join(root, rel);
    fs.mkdirSync(path.dirname(abs), { recursive: true });
    fs.writeFileSync(abs, text);
    written.push(rel);
  }
  return written;
}

export const USAGE = `Usage: ${COMMAND} [--check]`;

/**
 * Read the command-line arguments. Only `--check` is accepted, so a typo such as `--chek` stops
 * the run instead of writing files.
 * @param {string[]} argv the arguments after the script path
 * @returns {{ check: boolean } | { error: string }}
 */
export function parseArgs(argv) {
  const unknown = argv.filter((a) => a !== "--check");
  if (unknown.length > 0) {
    return { error: `gen-themes: unknown argument ${unknown.map((a) => JSON.stringify(a)).join(", ")}` };
  }
  return { check: argv.includes("--check") };
}

/**
 * Tell whether the script path Node was started with is this module. Both paths are resolved
 * through symlinks and junctions first, because a textual comparison fails through a link and the
 * script would then exit 0 having done nothing.
 * @param {string | undefined} started process.argv[1]
 * @param {string} self this module's file path
 * @returns {boolean}
 */
export function isEntry(started, self) {
  if (!started) return false;
  const real = (p) => {
    try {
      return fs.realpathSync(path.resolve(p));
    } catch {
      return path.resolve(p);
    }
  };
  const a = real(started);
  const b = real(self);
  // Windows paths are compared without case, because the drive letter's case can differ.
  return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
}

function main(argv) {
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
  const args = parseArgs(argv);
  if ("error" in args) {
    console.error(args.error);
    console.error(USAGE);
    return 2;
  }
  try {
    if (args.check) {
      const stale = check(root);
      if (stale.length > 0) {
        for (const rel of stale) console.error(`stale: ${rel}`);
        console.error(`Run ${COMMAND} to regenerate.`);
        return 1;
      }
      console.log("gen-themes: every output is up to date");
      return 0;
    }
    const written = write(root);
    for (const rel of written) console.log(`wrote ${rel}`);
    if (written.length === 0) console.log("gen-themes: every output is up to date");
    return 0;
  } catch (err) {
    console.error(`gen-themes: ${err.message}`);
    return 1;
  }
}

// Run only when started as a script, not when the test imports this module.
if (isEntry(process.argv[1], fileURLToPath(import.meta.url))) {
  process.exitCode = main(process.argv.slice(2));
}
