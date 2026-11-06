import { useMemo, useState } from "react";
import type { ButtonItem, DockSide, MenuDocument, ThemeName } from "../schema";
import { barColors, headerVariant, styleVars } from "../theme/css";
import { EffectsLayer, MacHeader, StatusBar, WindowBand } from "./frames";
import { ChoiceStrip, PreviewItem, type PreviewActions } from "./Items";
import {
  buttonLook,
  choiceLook,
  closeLook,
  labelVars,
  panelClasses,
  previewFor,
  StyleContext,
  usePreviewStyle,
} from "./look";
import "./MenuPreview.css";

const DOCK_OPTIONS: { label: string; value: DockSide }[] = [
  { label: "Top", value: "top" },
  { label: "Right", value: "right" },
  { label: "Bottom", value: "bottom" },
  { label: "Left", value: "left" },
];

function sectionTab(section: MenuDocument["sections"][number], tabs: string[] | undefined): string | undefined {
  if (!tabs || tabs.length === 0) {
    return undefined;
  }
  if (section.tab && tabs.includes(section.tab)) {
    return section.tab;
  }
  return tabs[0];
}

function seedFolds(doc: MenuDocument): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const section of doc.sections) {
    for (const item of section.items) {
      if (item.type === "fold") {
        out[`${section.id}.${item.id}`] = item.collapsed !== false;
      }
    }
  }
  return out;
}

function seedChecks(doc: MenuDocument): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  const walk = (sectionId: string, items: MenuDocument["sections"][number]["items"]) => {
    for (const item of items) {
      if (item.type === "checkbox") {
        out[`${sectionId}.${item.id}`] = item.default === true;
      } else if (item.type === "row" || item.type === "fold") {
        walk(sectionId, item.items);
      }
    }
  };
  for (const section of doc.sections) {
    walk(section.id, section.items);
  }
  return out;
}

function seedCollapsed(doc: MenuDocument): Record<string, boolean> {
  const out: Record<string, boolean> = {};
  for (const section of doc.sections) {
    if (section.collapsible) {
      out[section.id] = section.collapsed === true;
    }
  }
  return out;
}

/** The confirm card. Its buttons follow the button item rule (buttonLook), so a ghost theme outlines them. */
export function ConfirmCard({ item, onDismiss }: { item: ButtonItem; onDismiss: () => void }) {
  const ps = usePreviewStyle();
  const spec = item.confirm;
  if (!spec) {
    return null;
  }
  const ok = buttonLook(ps, { variant: spec.variant ?? item.variant ?? "danger" });
  const cancel = buttonLook(ps, { variant: "secondary" });
  return (
    <div className="mm-confirm-dim">
      <div className="mm-confirm-card">
        <div className="mm-confirm-pad">
          <p className="mm-confirm-title">{spec.title ?? "Are you sure?"}</p>
        </div>
        <div className="mm-confirm-rule" />
        {spec.message && (
          <>
            <div className="mm-confirm-pad">
              <p className="mm-confirm-msg">{spec.message}</p>
            </div>
            <div className="mm-confirm-rule" />
          </>
        )}
        <div className="mm-confirm-actions">
          <button type="button" className={`mm-btn mm-btn-inline ${cancel.className}`} style={cancel.style} onClick={onDismiss}>
            {spec.cancelLabel ?? "Cancel"}
          </button>
          <button type="button" className={`mm-btn mm-btn-inline ${ok.className}`} style={ok.style} onClick={onDismiss}>
            {spec.confirmLabel ?? "Confirm"}
          </button>
        </div>
      </div>
    </div>
  );
}

function hintText(document: MenuDocument): string {
  return `[${document.init.keyHint}] toggle menu`;
}

/**
 * The header in the resolved header variant (Build.Header). stock is today's title row and hint;
 * badge adds a square with the title's first letter; rule puts an accent bar under the title; badge,
 * plain, tape and strip end with a line. bar draws in the band across the top of the panel instead.
 */
function Header({ document, variant }: { document: MenuDocument; variant: string }) {
  const ps = usePreviewStyle();
  const title = document.init.title;
  // The window frames keep the hint as the first line of the content, under the title bar. The macOS
  // frame puts the lights and the title in a row and centres the hint (Build.Header).
  if (variant === "window" || variant === "xpbar" || variant === "classic") {
    return <p className="mm-hint mm-frame-hint">{hintText(document)}</p>;
  }
  if (variant === "mac") {
    return (
      <>
        <MacHeader title={title} />
        <p className="mm-hint mm-frame-hint mm-frame-hint-center">{hintText(document)}</p>
        {ps.resolved.header.line !== undefined && <div className="mm-header-line" />}
      </>
    );
  }
  const close = closeLook(ps);
  const closeButton = (
    <button type="button" className={`mm-btn mm-btn-inline mm-close ${close.className}`} style={close.style}>
      Close
    </button>
  );
  if (variant === "stock") {
    return (
      <>
        <div className="mm-title-row">
          <h2 className="mm-title">{title}</h2>
          {closeButton}
        </div>
        <p className="mm-hint">{hintText(document)}</p>
      </>
    );
  }
  const letter = (/[A-Za-z0-9]/.exec(title)?.[0] ?? "M").toUpperCase();
  return (
    <>
      <div className="mm-title-row">
        {(variant === "badge" || variant === "strip") && (
          <span className="mm-badge" aria-hidden="true">
            {letter}
          </span>
        )}
        <h2 className="mm-title">{title}</h2>
        {closeButton}
      </div>
      {variant === "rule" && <div className="mm-header-rule" />}
      <p className="mm-hint">{hintText(document)}</p>
      {variant !== "rule" && <div className="mm-header-line" />}
    </>
  );
}

/** The band across the top of a themed panel for the bar, tape and strip headers (TopBand in shell/build.lua). */
function TopBand({ document, variant }: { document: MenuDocument; variant: string }) {
  const ps = usePreviewStyle();
  if (variant === "tape") {
    return <div className="mm-band-tape" aria-hidden="true" />;
  }
  if (variant === "strip") {
    return <div className="mm-band-strip" aria-hidden="true" />;
  }
  if (variant === "window" || variant === "xpbar" || variant === "classic") {
    return <WindowBand title={document.init.title} variant={variant} />;
  }
  if (variant !== "bar") {
    return null;
  }
  const cursor = ps.resolved.motion?.cursor === true;
  const close = closeLook(ps, barColors(ps.resolved).text);
  return (
    <div className={`mm-band-bar${cursor ? " has-cursor" : ""}`}>
      <div className="mm-band-titles">
        <h2 className="mm-title">{document.init.title}</h2>
        <p className="mm-hint">{hintText(document)}</p>
      </div>
      {cursor && (
        // The cursor block follows the titles, and a spacer keeps Close at the right edge (Effects.Cursor).
        <>
          <span className="mm-cursor" style={{ background: ps.css(ps.resolved.palette.accentText) }} aria-hidden="true" />
          <span className="mm-band-spacer" />
        </>
      )}
      <button type="button" className={`mm-btn mm-btn-inline mm-close ${close.className}`} style={close.style}>
        Close
      </button>
    </div>
  );
}

export function MenuPreview({
  document,
  theme,
  onDockChange,
}: {
  document: MenuDocument;
  /** The preview's theme; the document's init.theme when not given. */
  theme?: ThemeName;
  onDockChange?: (dock: DockSide) => void;
}) {
  const themeId = theme ?? document.init.theme;
  const style = document.init.style;
  const ps = useMemo(() => previewFor(themeId, style), [themeId, style]);
  const variant = headerVariant(ps.resolved);
  const tabsLook = choiceLook(ps, "tabs", undefined);
  const tabs = document.init.tabs;
  const dock = document.init.dock;
  const [chosenTab, setActiveTab] = useState(tabs?.[0] ?? null);
  // The tab in use is the chosen one while it still exists, else the first, so a changed tab list needs no effect.
  const activeTab = tabs && tabs.length > 0 ? (chosenTab && tabs.includes(chosenTab) ? chosenTab : tabs[0]) : null;
  const [collapsed, setCollapsed] = useState(() => seedCollapsed(document));
  const [foldCollapsed, setFoldCollapsed] = useState(() => seedFolds(document));
  const [checks, setChecks] = useState(() => seedChecks(document));
  const [openDropdown, setOpenDropdown] = useState<string | null>(null);
  const [dockOpen, setDockOpen] = useState(false);
  const [confirm, setConfirm] = useState<ButtonItem | null>(null);

  const visible = useMemo(() => {
    return document.sections.filter((section) => {
      if (!tabs || !activeTab) {
        return true;
      }
      return sectionTab(section, tabs) === activeTab;
    });
  }, [document.sections, tabs, activeTab]);

  const actions: PreviewActions = {
    openDropdown,
    setOpenDropdown: (key) => {
      setDockOpen(false);
      setOpenDropdown(key);
    },
    foldCollapsed,
    toggleFold: (key) => {
      setFoldCollapsed((prev) => ({ ...prev, [key]: !prev[key] }));
    },
    checks,
    toggleCheck: (key) => {
      setChecks((prev) => ({ ...prev, [key]: !prev[key] }));
    },
    onConfirm: (item) => {
      setConfirm(item);
    },
  };

  const dockLabel = DOCK_OPTIONS.find((opt) => opt.value === dock)?.label ?? dock;

  return (
    <StyleContext.Provider value={ps}>
    <div className={`mm-stage dock-${dock}`}>
      <div
        className={panelClasses(ps.resolved, ps.style)}
        style={{ ...styleVars(ps.resolved), ...labelVars(ps) }}
        data-theme={ps.resolved.id}
        role="region"
        aria-label="Menu preview"
      >
        <TopBand document={document} variant={variant} />
        <div className="mm-scroll">
          {variant !== "bar" && <Header document={document} variant={variant} />}

          <p className="mm-hint mm-dock-cap">Dock</p>
          <div className="mm-drop">
            <button
              type="button"
              className="mm-drop-header"
              onClick={() => {
                setOpenDropdown(null);
                setDockOpen((open) => !open);
              }}
            >
              <span>{dockLabel}</span>
              <span className="mm-drop-arrow">{dockOpen ? "▲" : "▼"}</span>
            </button>
            {dockOpen && (
              <div className="mm-drop-list">
                {DOCK_OPTIONS.map((opt) => (
                  <button
                    key={opt.value}
                    type="button"
                    className={`mm-drop-opt${opt.value === dock ? " is-selected" : ""}`}
                    onClick={() => {
                      onDockChange?.(opt.value);
                      setDockOpen(false);
                    }}
                  >
                    {opt.label}
                  </button>
                ))}
              </div>
            )}
          </div>

          {tabs && tabs.length > 0 && tabsLook.variant !== "stock" && (
            <div className="mm-tabs-themed">
              <ChoiceStrip
                look={tabsLook}
                options={tabs.map((name) => ({
                  key: name,
                  label: name,
                  on: name === activeTab,
                  onClick: () => {
                    setActiveTab(name);
                    setOpenDropdown(null);
                    setDockOpen(false);
                  },
                }))}
              />
            </div>
          )}

          {tabs && tabs.length > 0 && tabsLook.variant === "stock" && (
            <div className="mm-tabs">
              {tabs.map((name) => {
                const active = name === activeTab;
                const chrome = buttonLook(ps, { active }).style;
                return (
                  <button
                    key={name}
                    type="button"
                    className="mm-tab"
                    style={chrome}
                    onClick={() => {
                      setActiveTab(name);
                      setOpenDropdown(null);
                      setDockOpen(false);
                    }}
                  >
                    {name}
                  </button>
                );
              })}
            </div>
          )}

          <div className="mm-head-pad" />

          {visible.length === 0 && <p className="mm-hint">No sections on this tab.</p>}

          {visible.map((section, sIndex) => {
            const isCollapsible = section.collapsible === true;
            const isCollapsed = isCollapsible && (collapsed[section.id] ?? section.collapsed === true);
            const title = `${section.prefix ? `${section.prefix} ` : ""}${section.title || section.id}`;
            return (
              <section key={section.id} className="mm-section">
                {isCollapsible ? (
                  <button
                    type="button"
                    className="mm-accordion mm-section-hdr"
                    onClick={() => {
                      setCollapsed((prev) => ({ ...prev, [section.id]: !prev[section.id] }));
                    }}
                  >
                    <span>{title}</span>
                    <span className="mm-mark">{isCollapsed ? "+" : "-"}</span>
                  </button>
                ) : (
                  <h3 className="mm-section-title">{title}</h3>
                )}
                {section.description && <p className="mm-section-desc">{section.description}</p>}
                {!isCollapsed && (
                  <div className="mm-section-body">
                    {section.items.map((item, index) => (
                      <PreviewItem
                        key={`${item.type}-${"id" in item ? item.id : index}`}
                        item={item}
                        sectionId={section.id}
                        actions={actions}
                        index={index}
                      />
                    ))}
                  </div>
                )}
                {sIndex < visible.length - 1 && <div className="mm-between" />}
              </section>
            );
          })}
          <div className="mm-foot" />
        </div>
        <StatusBar ps={ps} />
        <EffectsLayer />
        {ps.resolved.panel.corners === true && (
          <>
            <span className="mm-corner mm-corner-tl" aria-hidden="true" />
            <span className="mm-corner mm-corner-tr" aria-hidden="true" />
            <span className="mm-corner mm-corner-bl" aria-hidden="true" />
            <span className="mm-corner mm-corner-br" aria-hidden="true" />
          </>
        )}
        {confirm && (
          <ConfirmCard
            item={confirm}
            onDismiss={() => {
              setConfirm(null);
            }}
          />
        )}
      </div>
    </div>
    </StyleContext.Provider>
  );
}
