import type { ReactNode } from "react";
import type {
  ButtonItem,
  ButtonVariant,
  CheckboxItem,
  ColorpickerItem,
  ColorValue,
  DockSide,
  DropdownItem,
  FoldItem,
  Item,
  KeybindItem,
  MenuDocument,
  MultiselectItem,
  NumberItem,
  ProgressItem,
  RadioItem,
  Section,
  SliderItem,
  StepperItem,
  TextInputItem,
} from "../schema";
import {
  BUTTON_VARIANTS,
  DOCK_SIDES,
  KEY_GROUPS,
  LABEL_ALIGNS,
  LABEL_STYLES,
  SPACING_KEYS,
  isToggleKey,
  validateDocument,
} from "../schema";
import type { NodeRef } from "./model";
import { canMove, getItem, idCollision } from "./model";
import { formatOptions, parseOptions } from "./optionsText";
import { LookPanel, StylePanel } from "./StylePanel";

const VARIANTS = [...BUTTON_VARIANTS] as ButtonVariant[];

function Field({ label, children }: { label: string; children: ReactNode }) {
  return (
    <label className="ed-field">
      <span>{label}</span>
      {children}
    </label>
  );
}

function Text({
  label,
  value,
  onChange,
}: {
  label: string;
  value: string;
  onChange: (value: string) => void;
}) {
  return (
    <Field label={label}>
      <input
        type="text"
        value={value}
        onChange={(event) => {
          onChange(event.target.value);
        }}
      />
    </Field>
  );
}

function Toggle({
  label,
  checked,
  onChange,
}: {
  label: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}) {
  return (
    <label className="ed-check">
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => {
          onChange(event.target.checked);
        }}
      />
      {label}
    </label>
  );
}

// A number field that writes undefined when it is emptied, so an unset setting exports nothing.
function OptNumber({
  label,
  value,
  onChange,
}: {
  label: string;
  value: number | undefined;
  onChange: (value: number | undefined) => void;
}) {
  return (
    <Text
      label={label}
      value={value === undefined ? "" : String(value)}
      onChange={(text) => {
        const n = Number(text);
        onChange(text.trim() === "" || Number.isNaN(n) ? undefined : n);
      }}
    />
  );
}

// A true value is the library's default, so the field writes undefined for true and false for false.
function OptToggle({
  label,
  value,
  onChange,
}: {
  label: string;
  value: boolean | undefined;
  onChange: (value: boolean | undefined) => void;
}) {
  return <Toggle label={label} checked={value !== false} onChange={(on) => onChange(on ? undefined : false)} />;
}

function InitFields({
  document,
  onPatchInit,
}: {
  document: MenuDocument;
  onPatchInit: (patch: Partial<MenuDocument["init"]>) => void;
}) {
  const init = document.init;
  return (
    <>
      <Text label="Title" value={init.title} onChange={(title) => onPatchInit({ title })} />
      <Text label="Instance id" value={init.instanceId} onChange={(instanceId) => onPatchInit({ instanceId })} />
      <Field label="Toggle key">
        <select
          value={init.keyHint}
          onChange={(event) => {
            onPatchInit({ keyHint: event.target.value });
          }}
        >
          {!isToggleKey(init.keyHint) && <option value={init.keyHint}>{init.keyHint}</option>}
          {KEY_GROUPS.map((group) => (
            <optgroup key={group.label} label={group.label}>
              {group.keys.map((name) => (
                <option key={name} value={name}>
                  {name}
                </option>
              ))}
            </optgroup>
          ))}
        </select>
      </Field>
      <Field label="Dock">
        <select
          value={init.dock}
          onChange={(event) => {
            onPatchInit({ dock: event.target.value as DockSide });
          }}
        >
          {[...DOCK_SIDES].map((side) => (
            <option key={side} value={side}>
              {side}
            </option>
          ))}
        </select>
      </Field>
      <OptNumber label="Tooltip delay (ms, blank for 400)" value={init.tooltipDelayMs} onChange={(tooltipDelayMs) => onPatchInit({ tooltipDelayMs })} />
      <OptToggle label="Show the Close button" value={init.showClose} onChange={(showClose) => onPatchInit({ showClose })} />
      <OptNumber label="Cursor scale (1 or more, blank for 1)" value={init.cursorScale} onChange={(cursorScale) => onPatchInit({ cursorScale })} />
      <p className="ed-muted">Spacing in pixels. A blank field keeps the library's value.</p>
      {SPACING_KEYS.map((key) => (
        <OptNumber
          key={key}
          label={key}
          value={init.spacing?.[key]}
          onChange={(value) => {
            const next = { ...init.spacing, [key]: value };
            if (value === undefined) {
              delete next[key];
            }
            onPatchInit({ spacing: Object.keys(next).length > 0 ? next : undefined });
          }}
        />
      ))}
      <StylePanel document={document} onPatchInit={onPatchInit} />
    </>
  );
}

function TabFields({
  name,
  onRename,
}: {
  name: string;
  onRename: (name: string) => void;
}) {
  return <Text label="Name" value={name} onChange={onRename} />;
}

function SectionFields({
  section,
  tabs,
  onPatch,
}: {
  section: Section;
  tabs?: string[];
  onPatch: (patch: Partial<Section>) => void;
}) {
  return (
    <>
      <Text label="Id" value={section.id} onChange={(id) => onPatch({ id })} />
      <Text label="Title" value={section.title ?? ""} onChange={(title) => onPatch({ title })} />
      <Text label="Prefix (drawn before the title)" value={section.prefix ?? ""} onChange={(prefix) => onPatch({ prefix: prefix || undefined })} />
      <Text label="Description (one line under the title)" value={section.description ?? ""} onChange={(description) => onPatch({ description: description || undefined })} />
      {tabs && tabs.length > 0 && (
        <Field label="Tab">
          <select
            value={section.tab ?? ""}
            onChange={(event) => {
              onPatch({ tab: event.target.value });
            }}
          >
            <option value="">First tab</option>
            {tabs.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </Field>
      )}
      <Toggle
        label="Collapsible"
        checked={section.collapsible === true}
        onChange={(collapsible) => {
          onPatch({ collapsible, collapsed: collapsible ? section.collapsed === true : undefined });
        }}
      />
      <Toggle
        label="Start collapsed"
        checked={section.collapsed === true}
        onChange={(collapsed) => {
          onPatch({ collapsed, collapsible: collapsed ? true : section.collapsible });
        }}
      />
    </>
  );
}

function IdField({
  item,
  section,
  path,
  onPatch,
}: {
  item: { id?: string; label?: string };
  section: Section;
  path: number[];
  onPatch: (patch: Record<string, unknown>) => void;
}) {
  const id = item.id ?? "";
  const clash = idCollision(section, id, path);
  return (
    <>
      <Text
        label="Id"
        value={id}
        onChange={(next) => {
          onPatch({ id: next });
        }}
      />
      <p className="ed-muted">Auto from section + label if you leave this blank.</p>
      {clash && <p className="ed-warn">This id is already used in the section.</p>}
    </>
  );
}

function ItemFields({
  item,
  section,
  path,
  onPatch,
}: {
  item: Item;
  section: Section;
  path: number[];
  onPatch: (patch: Record<string, unknown>) => void;
}) {
  if (item.type === "separator") {
    return <p className="ed-muted">No fields.</p>;
  }
  if (item.type === "row") {
    return <p className="ed-muted">Row children are in the outline. Add button, checkbox, label, number, progress, slider, stepper, or text.</p>;
  }
  if (item.type === "label") {
    return (
      <>
        <Text label="Label" value={item.label} onChange={(label) => onPatch({ label })} />
        <IdField item={item} section={section} path={path} onPatch={onPatch} />
        <Field label="Style">
          <select value={item.style ?? "normal"} onChange={(event) => onPatch({ style: event.target.value === "normal" ? undefined : event.target.value })}>
            {[...LABEL_STYLES].map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </Field>
        <Field label="Align">
          <select value={item.align ?? "left"} onChange={(event) => onPatch({ align: event.target.value === "left" ? undefined : event.target.value })}>
            {[...LABEL_ALIGNS].map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </Field>
        <OptToggle label="Wrap long text" value={item.wrap} onChange={(wrap) => onPatch({ wrap })} />
      </>
    );
  }
  if (item.type === "fold") {
    const fold = item as FoldItem;
    return (
      <>
        <IdField item={fold} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={fold.label} onChange={(label) => onPatch({ label })} />
        <Toggle label="Start collapsed" checked={fold.collapsed !== false} onChange={(collapsed) => onPatch({ collapsed })} />
      </>
    );
  }
  if (item.type === "button") {
    const button = item as ButtonItem;
    return (
      <>
        <IdField item={button} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={button.label} onChange={(label) => onPatch({ label })} />
        <Field label="Variant">
          <select
            value={button.variant ?? "default"}
            onChange={(event) => {
              onPatch({ variant: event.target.value as ButtonVariant });
            }}
          >
            {VARIANTS.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </Field>

        <Toggle label="Active" checked={button.active === true} onChange={(active) => onPatch({ active })} />
        <Toggle
          label="Confirm first"
          checked={button.confirm !== undefined}
          onChange={(on) => {
            onPatch({
              confirm: on
                ? {
                    title: button.confirm?.title ?? "Are you sure?",
                    message: button.confirm?.message ?? "",
                    confirmLabel: button.confirm?.confirmLabel ?? "Confirm",
                  }
                : null,
            });
          }}
        />
        {button.confirm && (
          <>
            <Text
              label="Confirm title"
              value={button.confirm.title ?? ""}
              onChange={(title) => onPatch({ confirm: { ...button.confirm, title } })}
            />
            <Text
              label="Confirm message"
              value={button.confirm.message ?? ""}
              onChange={(message) => onPatch({ confirm: { ...button.confirm, message } })}
            />
            <Text
              label="Confirm label"
              value={button.confirm.confirmLabel ?? "Confirm"}
              onChange={(confirmLabel) => onPatch({ confirm: { ...button.confirm, confirmLabel } })}
            />
            <Text
              label="Cancel label (blank for Cancel)"
              value={button.confirm.cancelLabel ?? ""}
              onChange={(cancelLabel) => onPatch({ confirm: { ...button.confirm, cancelLabel: cancelLabel || undefined } })}
            />
            <Field label="Confirm button colour">
              <select
                value={button.confirm.variant ?? "default"}
                onChange={(event) =>
                  onPatch({
                    confirm: { ...button.confirm, variant: event.target.value === "default" ? undefined : (event.target.value as ButtonVariant) },
                  })
                }
              >
                {VARIANTS.map((name) => (
                  <option key={name} value={name}>
                    {name}
                  </option>
                ))}
              </select>
            </Field>
          </>
        )}
      </>
    );
  }
  if (item.type === "checkbox") {
    const box = item as CheckboxItem;
    return (
      <>
        <IdField item={box} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={box.label} onChange={(label) => onPatch({ label })} />
        <Toggle label="Default on" checked={box.default === true} onChange={(value) => onPatch({ default: value })} />
        <OptToggle label="Show ON or OFF after the label" value={box.showState} onChange={(showState) => onPatch({ showState })} />
      </>
    );
  }
  if (item.type === "dropdown") {
    const drop = item as DropdownItem;
    return (
      <>
        <IdField item={drop} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={drop.label} onChange={(label) => onPatch({ label })} />
        <Field label="Options (one per line, or label|value)">
          <textarea
            rows={5}
            value={formatOptions(drop.options)}
            onChange={(event) => {
              const options = parseOptions(event.target.value);
              onPatch({ options: options.length > 0 ? options : drop.options });
            }}
          />
        </Field>
        <Text label="Default" value={drop.default ?? ""} onChange={(value) => onPatch({ default: value || null })} />
        <Text
          label="Placeholder"
          value={drop.placeholder ?? ""}
          onChange={(placeholder) => onPatch({ placeholder: placeholder || undefined })}
        />
        <Toggle label="Searchable" checked={drop.searchable === true} onChange={(searchable) => onPatch({ searchable })} />
        <OptNumber label="Rows shown at once (blank for all)" value={drop.maxVisible} onChange={(maxVisible) => onPatch({ maxVisible })} />
        <OptNumber label="List height limit (px, blank for the default)" value={drop.listMaxHeight} onChange={(listMaxHeight) => onPatch({ listMaxHeight })} />
        <Toggle label="Allow no selection" checked={drop.allowEmpty === true} onChange={(allowEmpty) => onPatch({ allowEmpty: allowEmpty || undefined })} />
      </>
    );
  }
  if (item.type === "number") {
    const num = item as NumberItem;
    return (
      <>
        <IdField item={num} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={num.label} onChange={(label) => onPatch({ label })} />
        <Text
          label="Default"
          value={String(num.default ?? "")}
          onChange={(value) => onPatch({ default: value === "" ? undefined : Number(value) })}
        />
        <Text
          label="Min"
          value={num.min === undefined ? "" : String(num.min)}
          onChange={(value) => onPatch({ min: value === "" ? undefined : Number(value) })}
        />
        <Text
          label="Max"
          value={num.max === undefined ? "" : String(num.max)}
          onChange={(value) => onPatch({ max: value === "" ? undefined : Number(value) })}
        />
        <Toggle label="Integer" checked={num.integer === true} onChange={(integer) => onPatch({ integer })} />
        <OptNumber label="Step (adds minus and plus buttons)" value={num.step} onChange={(step) => onPatch({ step })} />
        <Text label="Prefix (inside the field, before the entry)" value={num.prefix ?? ""} onChange={(prefix) => onPatch({ prefix: prefix || undefined })} />
        <Text label="Suffix (inside the field, after the entry)" value={num.suffix ?? ""} onChange={(suffix) => onPatch({ suffix: suffix || undefined })} />
        <OptNumber label="Field width (px)" value={num.fieldWidth} onChange={(fieldWidth) => onPatch({ fieldWidth })} />
        <OptNumber label="Label width (px)" value={num.labelWidth} onChange={(labelWidth) => onPatch({ labelWidth })} />
        <OptNumber label="Change delay (ms, blank for 250)" value={num.debounceMs} onChange={(debounceMs) => onPatch({ debounceMs })} />
      </>
    );
  }
  if (item.type === "textinput") {
    const text = item as TextInputItem;
    return (
      <>
        <IdField item={text} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={text.label} onChange={(label) => onPatch({ label })} />
        <Text label="Default" value={text.default ?? ""} onChange={(value) => onPatch({ default: value })} />
        <Text
          label="Placeholder"
          value={text.placeholder ?? ""}
          onChange={(placeholder) => onPatch({ placeholder: placeholder || undefined })}
        />
        <OptNumber label="Longest text (characters)" value={text.maxLength} onChange={(maxLength) => onPatch({ maxLength })} />
        <OptNumber label="Field width (px)" value={text.fieldWidth} onChange={(fieldWidth) => onPatch({ fieldWidth })} />
        <OptNumber label="Label width (px)" value={text.labelWidth} onChange={(labelWidth) => onPatch({ labelWidth })} />
        <OptNumber label="Change delay (ms, blank for 250)" value={text.debounceMs} onChange={(debounceMs) => onPatch({ debounceMs })} />
      </>
    );
  }
  if (item.type === "slider") {
    const slider = item as SliderItem;
    // Min and max are required by the schema, so an emptied field keeps the old number rather than
    // writing undefined, which the validator would reject on export.
    const numberOr = (value: string, fallback: number) => (value === "" ? fallback : Number(value));
    return (
      <>
        <IdField item={slider} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={slider.label} onChange={(label) => onPatch({ label })} />
        <Text label="Min" value={String(slider.min)} onChange={(value) => onPatch({ min: numberOr(value, slider.min) })} />
        <Text label="Max" value={String(slider.max)} onChange={(value) => onPatch({ max: numberOr(value, slider.max) })} />
        <Text
          label="Step"
          value={slider.step === undefined ? "" : String(slider.step)}
          onChange={(value) => onPatch({ step: value === "" ? undefined : Number(value) })}
        />
        <Text
          label="Default"
          value={slider.default === undefined ? "" : String(slider.default)}
          onChange={(value) => onPatch({ default: value === "" ? undefined : Number(value) })}
        />
        <Text
          label="Format (string.format pattern, blank for the default)"
          value={slider.format ?? ""}
          onChange={(format) => onPatch({ format: format || undefined })}
        />
        <Toggle label="Integer" checked={slider.integer === true} onChange={(integer) => onPatch({ integer })} />
        <Toggle label="Live (apply while dragging)" checked={slider.live === true} onChange={(live) => onPatch({ live })} />
        <OptToggle label="Show the value" value={slider.showValue} onChange={(showValue) => onPatch({ showValue })} />
        <OptNumber label="Label width (px)" value={slider.labelWidth} onChange={(labelWidth) => onPatch({ labelWidth })} />
      </>
    );
  }
  if (item.type === "stepper") {
    const stepper = item as StepperItem;
    return (
      <>
        <IdField item={stepper} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={stepper.label} onChange={(label) => onPatch({ label })} />
        <OptNumber label="Min (blank for none)" value={stepper.min} onChange={(min) => onPatch({ min })} />
        <OptNumber label="Max (blank for none)" value={stepper.max} onChange={(max) => onPatch({ max })} />
        <OptNumber label="Step (blank for 1)" value={stepper.step} onChange={(step) => onPatch({ step })} />
        <OptNumber label="Default" value={stepper.default} onChange={(value) => onPatch({ default: value })} />
        <Text
          label="Format (string.format pattern, blank for the default)"
          value={stepper.format ?? ""}
          onChange={(format) => onPatch({ format: format || undefined })}
        />
        <Toggle label="Integer" checked={stepper.integer === true} onChange={(integer) => onPatch({ integer })} />
      </>
    );
  }
  if (item.type === "progress") {
    const progress = item as ProgressItem;
    return (
      <>
        <IdField item={progress} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={progress.label} onChange={(label) => onPatch({ label })} />
        <OptNumber label="Min (blank for 0)" value={progress.min} onChange={(min) => onPatch({ min })} />
        <OptNumber label="Max (blank for 1)" value={progress.max} onChange={(max) => onPatch({ max })} />
        <OptNumber label="Default" value={progress.default} onChange={(value) => onPatch({ default: value })} />
        <Text
          label="Format (string.format pattern, blank for the percent)"
          value={progress.format ?? ""}
          onChange={(format) => onPatch({ format: format || undefined })}
        />
        <Field label="Variant">
          <select
            value={progress.variant ?? "default"}
            onChange={(event) => {
              onPatch({ variant: event.target.value as ButtonVariant });
            }}
          >
            {VARIANTS.map((name) => (
              <option key={name} value={name}>
                {name}
              </option>
            ))}
          </select>
        </Field>
      </>
    );
  }
  if (item.type === "radio") {
    const radio = item as RadioItem;
    return (
      <>
        <IdField item={radio} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={radio.label} onChange={(label) => onPatch({ label })} />
        <Field label="Options (one per line, or label|value)">
          <textarea
            rows={5}
            value={formatOptions(radio.options)}
            onChange={(event) => {
              const options = parseOptions(event.target.value);
              onPatch({ options: options.length > 0 ? options : radio.options });
            }}
          />
        </Field>
        <Text label="Default" value={radio.default ?? ""} onChange={(value) => onPatch({ default: value || undefined })} />
        <Toggle label="Inline (options on one line)" checked={radio.inline === true} onChange={(inline) => onPatch({ inline })} />
      </>
    );
  }
  if (item.type === "colorpicker") {
    const picker = item as ColorpickerItem;
    const color: ColorValue = picker.default ?? { R: 1, G: 1, B: 1, A: 1 };
    const keys = picker.alpha === false ? (["R", "G", "B"] as const) : (["R", "G", "B", "A"] as const);
    return (
      <>
        <IdField item={picker} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={picker.label} onChange={(label) => onPatch({ label })} />
        <p className="ed-muted">Default colour</p>
        {keys.map((key) => (
          <Field key={key} label={`${key} ${color[key].toFixed(2)}`}>
            <input
              type="range"
              min={0}
              max={1}
              step={0.01}
              value={color[key]}
              onChange={(event) => onPatch({ default: { ...color, [key]: Number(event.target.value) } })}
            />
          </Field>
        ))}
        <OptToggle label="Alpha slider" value={picker.alpha} onChange={(alpha) => onPatch({ alpha })} />
      </>
    );
  }
  if (item.type === "multiselect") {
    const multi = item as MultiselectItem;
    // The default is picked from the options, so a typo cannot name a value that is not one.
    const values = multi.options.map((opt) => (typeof opt === "string" ? opt : String(opt.value ?? opt.label ?? "")));
    const checked = multi.default ?? [];
    return (
      <>
        <IdField item={multi} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={multi.label} onChange={(label) => onPatch({ label })} />
        <Field label="Options (one per line, or label|value)">
          <textarea
            rows={5}
            value={formatOptions(multi.options)}
            onChange={(event) => {
              const options = parseOptions(event.target.value);
              onPatch({ options: options.length > 0 ? options : multi.options });
            }}
          />
        </Field>
        <p className="ed-muted">Checked by default</p>
        {values.map((value) => (
          <Toggle
            key={value}
            label={value}
            checked={checked.includes(value)}
            onChange={(on) => {
              const next = values.filter((name) => (name === value ? on : checked.includes(name)));
              onPatch({ default: next.length > 0 ? next : undefined });
            }}
          />
        ))}
        <OptNumber label="Columns (1 to 4, blank for 1)" value={multi.columns} onChange={(columns) => onPatch({ columns })} />
      </>
    );
  }
  if (item.type === "keybind") {
    const keybind = item as KeybindItem;
    return (
      <>
        <IdField item={keybind} section={section} path={path} onPatch={onPatch} />
        <Text label="Label" value={keybind.label} onChange={(label) => onPatch({ label })} />
        <Text
          label="Default key (FKey name such as F7, blank for none)"
          value={keybind.default ?? ""}
          onChange={(value) => onPatch({ default: value })}
        />
        <Toggle
          label="Allow modifiers"
          checked={keybind.allowModifiers === true}
          onChange={(allowModifiers) => onPatch({ allowModifiers })}
        />
      </>
    );
  }
  return null;
}

// Every item but a separator can carry a tooltip, so the field sits beside the type fields rather
// than inside each branch above.
function TooltipField({ item, onPatch }: { item: Item; onPatch: (patch: Record<string, unknown>) => void }) {
  if (item.type === "separator") {
    return null;
  }
  const tooltip = "tooltip" in item && typeof item.tooltip === "string" ? item.tooltip : "";
  return <Text label="Tooltip" value={tooltip} onChange={(value) => onPatch({ tooltip: value || undefined })} />;
}

// Every item can be disabled or hidden, so these two sit beside the type fields too.
function StateFields({ item, onPatch }: { item: Item; onPatch: (patch: Record<string, unknown>) => void }) {
  return (
    <>
      <OptToggle label="Enabled" value={item.enabled} onChange={(enabled) => onPatch({ enabled })} />
      <OptToggle label="Visible" value={item.visible} onChange={(visible) => onPatch({ visible })} />
    </>
  );
}

export function Inspector({
  document,
  selection,
  onPatchInit,
  onRenameTab,
  onPatchSection,
  onPatchItem,
  onMove,
  onRemove,
}: {
  document: MenuDocument;
  selection: NodeRef | null;
  onPatchInit: (patch: Partial<MenuDocument["init"]>) => void;
  onRenameTab: (index: number, name: string) => void;
  onPatchSection: (index: number, patch: Partial<Section>) => void;
  onPatchItem: (sel: Extract<NodeRef, { kind: "item" }>, patch: Record<string, unknown>) => void;
  onMove: (delta: -1 | 1) => void;
  onRemove: () => void;
}) {
  const issues = validateDocument(document);
  const canDelete = selection !== null && selection.kind !== "init";
  return (
    <>
      {selection && selection.kind !== "init" && (
        <div className="ed-ops">
          <button type="button" disabled={!canMove(document, selection, -1)} onClick={() => onMove(-1)}>
            Up
          </button>
          <button type="button" disabled={!canMove(document, selection, 1)} onClick={() => onMove(1)}>
            Down
          </button>
          <button type="button" disabled={!canDelete} onClick={onRemove}>
            Remove
          </button>
        </div>
      )}
      {selection === null && <p className="ed-muted">Select something in the outline.</p>}
      {selection?.kind === "init" && <InitFields document={document} onPatchInit={onPatchInit} />}
      {selection?.kind === "tab" && document.init.tabs && (
        <TabFields name={document.init.tabs[selection.index] ?? ""} onRename={(name) => onRenameTab(selection.index, name)} />
      )}
      {selection?.kind === "section" && document.sections[selection.index] && (
        <SectionFields
          section={document.sections[selection.index]}
          tabs={document.init.tabs}
          onPatch={(patch) => onPatchSection(selection.index, patch)}
        />
      )}
      {selection?.kind === "item" && (() => {
        const item = getItem(document, selection);
        const section = document.sections[selection.sectionIndex];
        if (!item || !section) {
          return <p className="ed-muted">Missing item.</p>;
        }
        return (
          <>
            <ItemFields item={item} section={section} path={selection.path} onPatch={(patch) => onPatchItem(selection, patch)} />
            <TooltipField item={item} onPatch={(patch) => onPatchItem(selection, patch)} />
            <StateFields item={item} onPatch={(patch) => onPatchItem(selection, patch)} />
            <LookPanel document={document} selection={selection} item={item} onPatchItem={(patch) => onPatchItem(selection, patch)} />
          </>
        );
      })()}
      {issues.length > 0 && (
        <ul className="ed-issues">
          {issues.slice(0, 6).map((issue) => (
            <li key={`${issue.path}:${issue.message}`}>
              {issue.path}: {issue.message}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
