/// <reference types="node" />
import { readFileSync, readdirSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { FIELDS } from "./fields.generated";
import { PRESET_ORDER } from "./presets.generated";
import { OBJECT_TYPES, forItem, legacyColors, resolve, type ResolvedStyle } from "./resolve";
import { DARK, LIGHT, PANEL_PAD, THEME_KEYS, preset } from "./tokens";

// The fixtures are the same files tooling/lua/style_spec.lua runs, so both resolvers are held equal.
const REPO = new URL("../../../", import.meta.url);
const FIXTURE_DIR = new URL("tooling/lua/fixtures/style/", REPO);

type Fixture = {
  input: { theme?: unknown; style?: unknown; colors?: unknown; look?: Record<string, unknown>; lookType?: string };
  expect: Record<string, unknown>;
};

function fixtureNames(): string[] {
  return readdirSync(FIXTURE_DIR)
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.slice(0, -".json".length))
    .sort();
}

function readFixture(name: string): Fixture {
  return JSON.parse(readFileSync(new URL(`${name}.json`, FIXTURE_DIR), "utf8")) as Fixture;
}

function getPath(t: unknown, path: string): unknown {
  let node = t;
  for (const segment of path.split(".")) {
    if (typeof node !== "object" || node === null) {
      return undefined;
    }
    node = (node as Record<string, unknown>)[segment];
  }
  return node;
}

// style_spec.lua's Near: expected values are written to 4 decimals, so a number matches within half of
// the last digit, and a table matches only with exactly the expected keys.
function near(got: unknown, want: unknown): boolean {
  if (typeof want === "number") {
    return typeof got === "number" && Math.abs(got - want) <= 0.000051;
  }
  if (typeof want !== "object" || want === null) {
    return got === want;
  }
  if (typeof got !== "object" || got === null) {
    return false;
  }
  const g = got as Record<string, unknown>;
  const w = want as Record<string, unknown>;
  const gotKeys = Object.keys(g).filter((k) => g[k] !== undefined);
  return Object.keys(w).every((k) => near(g[k], w[k])) && gotKeys.every((k) => k in w);
}

function round4(v: unknown): unknown {
  if (typeof v === "number") {
    return Math.round(v * 10000) / 10000;
  }
  if (Array.isArray(v)) {
    return v.map(round4);
  }
  if (typeof v === "object" && v !== null) {
    return Object.fromEntries(Object.entries(v).map(([k, inner]) => [k, round4(inner)]));
  }
  return v;
}

function luaFixtureList(): string[] {
  const spec = readFileSync(new URL("tooling/lua/style_spec.lua", REPO), "utf8");
  const block = /local FIXTURES = \{([\s\S]*?)\}/.exec(spec);
  if (block === null) {
    throw new Error("style_spec.lua has no FIXTURES list");
  }
  return [...block[1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
}

describe("resolve against the shared style fixtures", () => {
  it("runs the same fixture list as style_spec.lua", () => {
    expect(fixtureNames()).toEqual(luaFixtureList());
  });

  for (const name of fixtureNames()) {
    it(`style fixture ${name}`, () => {
      const { input, expect: want } = readFixture(name);
      const resolved = resolve(
        input.theme as Parameters<typeof resolve>[0],
        input.style as Parameters<typeof resolve>[1],
        input.colors as Parameters<typeof resolve>[2],
      ) as ResolvedStyle & Record<string, unknown>;
      if (input.look !== undefined && input.lookType !== undefined) {
        resolved[input.lookType] = forItem(resolved, input.lookType, input.look);
      }
      const mismatches = Object.keys(want)
        .sort()
        .filter((path) => !near(getPath(resolved, path), want[path]))
        .map((path) => `${path} = ${JSON.stringify(round4(getPath(resolved, path)))}`);
      expect(mismatches, name).toEqual([]);
    });
  }
});

describe("resolve", () => {
  it("lists every object type of the field list in its resolution order", () => {
    expect([...OBJECT_TYPES].sort()).toEqual(Object.keys(FIELDS.types).sort());
  });

  it("resolves every preset into a complete style with linear colours", () => {
    for (const id of PRESET_ORDER) {
      const resolved = resolve(id);
      expect(resolved.id).toBe(id);
      for (const typeName of OBJECT_TYPES) {
        for (const [field, kind] of Object.entries(FIELDS.types[typeName])) {
          const value = resolved[typeName][field];
          if (kind === "color" && value !== undefined) {
            expect(typeof value.R, `${id} ${typeName}.${field}`).toBe("number");
          }
        }
      }
    }
  });

  it("raises an error listing every preset id for an unknown theme", () => {
    expect(() => resolve("nope")).toThrow(`unknown theme "nope"; choose one of: ${PRESET_ORDER.join(", ")}`);
  });

  it("raises an error naming an unknown type, field or kind in the style", () => {
    expect(() => resolve("slate", { wobble: {} })).toThrow("style.wobble: unknown object type");
    expect(() => resolve("slate", { button: { wobble: 1 } })).toThrow("style.button.wobble: unknown field");
    expect(() => resolve("slate", { button: { radius: "big" } })).toThrow("style.button.radius: must be radius");
    expect(() => resolve("slate", { button: "nope" })).toThrow("style.button: unknown preset nope");
  });

  it("copies a free-form table's __proto__ key as an own key, not as the prototype", () => {
    const ramp = JSON.parse('{ "__proto__": { "polluted": "#FF0000" }, "a": "#00FF00" }') as Record<string, unknown>;
    const resolved = resolve("slate", { progress: { ramp } });
    const copy = resolved.progress.ramp as Record<string, unknown>;
    expect(Object.getPrototypeOf(copy)).toBe(Object.prototype);
    expect(Object.hasOwn(copy, "__proto__")).toBe(true);
    expect((copy as { polluted?: unknown }).polluted).toBeUndefined();
    expect(copy.a).toEqual({ R: 0, G: 1, B: 0, A: 1 });
  });

  it("reads a colour channel string as Lua's tonumber does, decimal only", () => {
    const resolved = resolve("slate", undefined, {
      panelBg: { R: "0.5", G: "Infinity", B: "0b11", A: " 1e0 " } as unknown as string,
    });
    expect(resolved.panel.fill).toEqual({ R: 0.5, G: 0, B: 0, A: 1 });
  });

  it("does not change the resolved style when an item look is merged", () => {
    const resolved = resolve("slate");
    const look = forItem(resolved, "button", { radius: 2 });
    expect(look.radius).toBe(2);
    expect(resolved.button.radius).toBe(8);
  });
});

describe("preset colour tokens", () => {
  it("keeps the literal light and dark tables", () => {
    expect(preset("light")).toBe(LIGHT);
    expect(preset("dark")).toBe(DARK);
    expect(PANEL_PAD.light).toEqual({ left: 20, top: 18, right: 20, bottom: 18 });
  });

  it("reads light and dark back from their resolved styles unchanged", () => {
    for (const [name, table] of [
      ["light", LIGHT],
      ["dark", DARK],
    ] as const) {
      const back = legacyColors(resolve(name));
      for (const key of THEME_KEYS) {
        expect(back[key], `${name} ${key}`).toEqual(table[key]);
      }
    }
  });

  it("derives every token for another preset from its resolved style", () => {
    const slate = preset("slate");
    for (const key of THEME_KEYS) {
      expect(typeof slate[key].R, key).toBe("number");
    }
    expect(slate.panelBg).toEqual(resolve("slate").panel.fill);
    expect(PANEL_PAD.slate).toEqual({ left: 18, top: 18, right: 18, bottom: 18 });
  });
});
