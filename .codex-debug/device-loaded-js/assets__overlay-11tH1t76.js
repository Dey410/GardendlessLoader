import{t as e}from"./logger-_0kcFG-y.js";import{d as t,h as n,m as r,p as i,r as a,u as o}from"./settings-store-ClY3sNI-.js";import{a as s,i as c,r as l}from"./i18n-CtLjZ535.js";import{t as u}from"./data-drawer-_m_J4ofg.js";var d=`
:root {
    --gp-font-ui: "Segoe UI", "Noto Sans", system-ui, -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
    --gp-font-mono: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "DejaVu Sans Mono", monospace;
}

/* ===== Overlay Container ===== */
#gp-overlay {
    position: fixed;
    top: 0; left: 0;
    width: min(420px, 92vw);
    height: 100%;
    background: rgba(2, 6, 23, 0.96);
    color: #f1f5f9;
    z-index: 99999;
    transform: translateX(-100%);
    transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1);
    font-family: var(--gp-font-ui);
    font-variant-numeric: tabular-nums;
    font-size: 13px;
    display: flex;
    flex-direction: column;
    box-shadow: 4px 0 24px rgba(0,0,0,0.6);
    user-select: text;
    text-align: left;
}
#gp-overlay.gp-open {
    transform: translateX(0);
}

/* ===== Header ===== */
.gp-header {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
}
.gp-logo {
    font-weight: 700;
    font-size: 16px;
    color: #fff;
    letter-spacing: 0.5px;
}
.gp-status {
    margin-left: auto;
    font-size: 11px;
    color: #4a9eff;
    flex: 1;
    min-width: 0;
    max-width: 160px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    text-align: right;
}
.gp-close-btn {
    background: none;
    border: none;
    color: #888;
    font-size: 18px;
    cursor: pointer;
    padding: 0 4px;
    line-height: 1;
    transition: color 0.15s;
}
.gp-close-btn:hover {
    color: #fff;
}

/* ===== Tab Bar ===== */
.gp-tabs {
    display: flex;
    flex-wrap: nowrap;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
    padding: 0 2px;
}
.gp-tab {
    background: none;
    border: none;
    color: #888;
    font-size: 12px;
    font-family: inherit;
    padding: 8px 12px;
    min-height: 36px;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    white-space: nowrap;
    transition: color 0.15s, border-color 0.15s;
    flex: 0 0 auto;
}
.gp-tab:hover {
    color: #ccc;
}
.gp-tab.gp-tab-active {
    color: #fff;
    border-bottom-color: #4a9eff;
}

/* ===== Content Area ===== */
.gp-content {
    flex: 1;
    overflow-y: auto;
    padding: 14px 16px 16px;
    scroll-padding-bottom: 24px;
}

.gp-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 9px 12px;
    border-top: 1px solid rgba(255,255,255,0.08);
    background: rgba(255,255,255,0.03);
    flex-shrink: 0;
}
.gp-footer-version {
    font-size: 11px;
    color: #80889b;
    white-space: nowrap;
}
.gp-footer-right {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    flex-wrap: wrap;
    justify-content: flex-end;
}
.gp-footer-update,
.gp-footer-refresh {
    background: none;
    border: none;
    color: #8d97ab;
    font: inherit;
    padding: 0;
}
.gp-footer-update {
    font-size: 11px;
    max-width: 180px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    cursor: default;
}
.gp-footer-update:disabled {
    opacity: 1;
}
.gp-footer-update-hot {
    color: #4a9eff;
    cursor: pointer;
}
.gp-footer-update-hot:hover {
    color: #7cb9ff;
    text-decoration: underline;
}
.gp-footer-refresh {
    font-size: 14px;
    line-height: 1;
    cursor: pointer;
    transition: color 0.15s, transform 0.15s;
}
.gp-footer-refresh:hover:not(:disabled) {
    color: #d8e6ff;
    transform: rotate(20deg);
}
.gp-footer-refresh:disabled {
    cursor: default;
    opacity: 0.7;
}
.gp-spinning {
    animation: gp-next-spin 0.9s linear infinite;
}

@keyframes gp-next-spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
}

/* ===== Scrollbar ===== */
#gp-overlay ::-webkit-scrollbar { width: 5px; }
#gp-overlay ::-webkit-scrollbar-track { background: transparent; }
#gp-overlay ::-webkit-scrollbar-thumb { background: rgba(255,255,255,0.15); border-radius: 3px; }
#gp-overlay ::-webkit-scrollbar-thumb:hover { background: rgba(255,255,255,0.25); }

/* ===== Hotkey Hint Badge ===== */
.gp-f1-hint {
    position: fixed;
    top: 8px; left: 8px;
    background: rgba(16,16,24,0.85);
    color: #888;
    font-family: var(--gp-font-ui);
    font-size: 10px;
    padding: 3px 7px;
    border-radius: 4px;
    z-index: 99998;
    cursor: pointer;
    transition: opacity 0.2s, color 0.15s;
    pointer-events: auto;
}
.gp-f1-hint:hover {
    color: #ccc;
}
.gp-f1-hint.gp-hidden {
    opacity: 0;
    pointer-events: none;
}

/* ===== Components: Button ===== */
.gp-btn {
    background: rgba(74,158,255,0.15);
    color: #4a9eff;
    border: 1px solid rgba(74,158,255,0.3);
    border-radius: 4px;
    padding: 6px 12px;
    min-height: 32px;
    font-size: 12px;
    font-family: inherit;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
    line-height: 1.2;
}
.gp-btn:hover {
    background: rgba(74,158,255,0.25);
    border-color: rgba(74,158,255,0.5);
}
.gp-btn:active {
    background: rgba(74,158,255,0.35);
}
.gp-btn-danger {
    background: rgba(244,67,54,0.12);
    color: #f44336;
    border-color: rgba(244,67,54,0.3);
}
.gp-btn-danger:hover {
    background: rgba(244,67,54,0.22);
    border-color: rgba(244,67,54,0.5);
}
.gp-btn-success {
    background: rgba(76,175,80,0.12);
    color: #4caf50;
    border-color: rgba(76,175,80,0.3);
}
.gp-btn-success:hover {
    background: rgba(76,175,80,0.22);
    border-color: rgba(76,175,80,0.5);
}
.gp-btn-sm {
    padding: 4px 9px;
    font-size: 11px;
    min-height: 28px;
}
.gp-btn-row {
    display: flex;
    gap: 8px;
    flex-wrap: wrap;
}

/* ===== Components: Toggle ===== */
.gp-toggle-wrap {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 4px 0;
}
.gp-toggle-label {
    font-size: 12px;
    color: #ccc;
    line-height: 1.4;
}
.gp-toggle {
    position: relative;
    width: 36px; height: 18px;
    background: rgba(255,255,255,0.12);
    border-radius: 9px;
    cursor: pointer;
    transition: background 0.2s;
    flex-shrink: 0;
}
.gp-toggle.gp-toggle-on {
    background: rgba(74,158,255,0.5);
}
.gp-toggle-knob {
    position: absolute;
    top: 2px; left: 2px;
    width: 14px; height: 14px;
    background: #e0e0e0;
    border-radius: 50%;
    transition: transform 0.2s;
}
.gp-toggle.gp-toggle-on .gp-toggle-knob {
    transform: translateX(18px);
    background: #fff;
}

/* ===== Components: Slider ===== */
.gp-slider-wrap {
    padding: 4px 0;
}
.gp-slider-header {
    display: flex;
    justify-content: space-between;
    margin-bottom: 4px;
}
.gp-slider-label { font-size: 12px; color: #ccc; }
.gp-slider-value { font-size: 11px; color: #4a9eff; font-weight: 600; }
.gp-slider {
    -webkit-appearance: none;
    width: 100%; height: 4px;
    background: rgba(255,255,255,0.12);
    border-radius: 2px;
    outline: none;
}
.gp-slider::-webkit-slider-thumb {
    -webkit-appearance: none;
    width: 14px; height: 14px;
    background: #4a9eff;
    border-radius: 50%;
    cursor: pointer;
}

/* ===== Components: Input ===== */
.gp-input-wrap {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
}
.gp-input-label {
    font-size: 12px;
    color: #ccc;
    white-space: nowrap;
    min-width: 92px;
}
.gp-input {
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 4px 8px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    transition: border-color 0.15s;
    width: 100%;
    min-width: 0;
}
.gp-input:focus {
    border-color: rgba(74,158,255,0.5);
}

/* ===== Components: Select ===== */
.gp-select-wrap {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 4px 0;
}
.gp-select-label {
    font-size: 12px;
    color: #ccc;
    white-space: nowrap;
    min-width: 92px;
}
.gp-select {
    -webkit-appearance: none;
    appearance: none;
    background-color: rgba(30,30,45,0.95);
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='10' height='6' viewBox='0 0 10 6'%3E%3Cpath d='M0 0l5 6 5-6z' fill='%23888'/%3E%3C/svg%3E");
    background-repeat: no-repeat;
    background-position: right 8px center;
    background-size: 10px 6px;
    border: 1px solid rgba(255,255,255,0.18);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 4px 26px 4px 8px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    cursor: pointer;
    width: 100%;
    min-width: 0;
}
.gp-select:focus {
    border-color: rgba(74,158,255,0.5);
}
.gp-select option {
    background-color: #1e1e2e;
    color: #e0e0e0;
}
.gp-select option:checked {
    background-color: #1a4a8a;
    color: #ffffff;
}

/* ===== Components: Section ===== */
.gp-section {
    margin-bottom: 12px;
    padding: 10px 12px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.05);
}
.gp-section-title {
    width: 100%;
    font-size: 11px;
    font-weight: 600;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    margin-bottom: 8px;
    padding: 0 0 6px;
    border-bottom: 1px solid rgba(255,255,255,0.06);
    cursor: pointer;
    user-select: none;
    display: flex;
    align-items: center;
    gap: 6px;
    background: none;
    border-top: none;
    border-left: none;
    border-right: none;
    text-align: left;
}
.gp-section-arrow {
    font-size: 9px;
    transition: transform 0.15s;
}
.gp-section.gp-collapsed .gp-section-arrow {
    transform: rotate(-90deg);
}
.gp-section-body {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.gp-section.gp-collapsed .gp-section-body {
    display: none;
}

/* ===== Components: Badge ===== */
.gp-badge {
    display: inline-block;
    font-size: 10px;
    font-weight: 600;
    padding: 1px 6px;
    border-radius: 3px;
    line-height: 1.4;
}
.gp-badge-info { background: rgba(74,158,255,0.2); color: #4a9eff; }
.gp-badge-success { background: rgba(76,175,80,0.2); color: #4caf50; }
.gp-badge-warning { background: rgba(255,152,0,0.2); color: #ff9800; }
.gp-badge-error { background: rgba(244,67,54,0.2); color: #f44336; }

/* ===== Components: List ===== */
.gp-list {
    display: flex;
    flex-direction: column;
    gap: 2px;
}
.gp-list-item {
    padding: 8px 10px;
    border-radius: 6px;
    font-size: 12px;
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
}
.gp-list-item .gp-text-mono {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
    flex: 1;
}
.gp-list-item .gp-text-muted {
    flex-shrink: 0;
    white-space: nowrap;
}
.gp-list-item:hover {
    background: rgba(255,255,255,0.04);
}

/* ===== Components: Search ===== */
.gp-search-wrap {
    padding: 4px 0 8px;
}
.gp-search {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    color: #e0e0e0;
    padding: 6px 10px;
    font-size: 12px;
    font-family: inherit;
    outline: none;
    box-sizing: border-box;
}
.gp-search:focus {
    border-color: rgba(74,158,255,0.5);
}

/* ===== Utilities ===== */
.gp-text-muted { color: #666; font-size: 11px; }
.gp-text-mono { font-family: var(--gp-font-mono); font-size: 11px; }
.gp-mt-8 { margin-top: 8px; }
.gp-mb-8 { margin-bottom: 8px; }
.gp-gap-4 { gap: 4px; }
.gp-code {
    font-family: var(--gp-font-mono);
    font-size: 11px;
    background: rgba(0,0,0,0.35);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 4px;
    padding: 8px 10px;
    margin: 4px 0;
    white-space: pre;
    overflow-x: auto;
    line-height: 1.5;
    color: #b0c9e0;
    display: block;
    text-align: left;
    user-select: text;
    cursor: text;
}

/* ===== Pack Card ===== */
.gp-pack-card {
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr) auto;
    align-items: flex-start;
    gap: 10px;
    padding: 10px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.06);
}
.gp-pack-card:hover {
    background: rgba(255,255,255,0.055);
}
.gp-pack-thumb {
    width: 44px;
    height: 44px;
    flex-shrink: 0;
    border-radius: 4px;
    background: rgba(255,255,255,0.06);
    overflow: hidden;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 20px;
    line-height: 1;
}
.gp-pack-thumb-fallback {
    font-size: 11px;
    font-weight: 700;
    letter-spacing: 0.08em;
    color: #9cdcfe;
}
.gp-pack-info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 4px;
}
.gp-pack-name-row {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 8px;
}
.gp-pack-name {
    font-weight: 600;
    font-size: 12px;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    line-height: 1.35;
}
.gp-pack-badge-row {
    display: flex;
    align-items: center;
    gap: 4px;
    flex-wrap: wrap;
}
.gp-pack-ctrl {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex-shrink: 0;
}
.gp-pack-requirement-warning {
    color: #ffb74d;
    font-size: 11px;
    line-height: 1.35;
}

/* ===== Data Detail Drawer ===== */
.gp-drawer {
    position: absolute;
    top: 0;
    left: 100%;
    width: min(680px, calc(100vw - 460px));
    min-width: 360px;
    max-width: calc(100vw - 32px);
    height: 100%;
    background: rgba(16, 16, 24, 0.95);
    backdrop-filter: blur(10px);
    border: 1px solid rgba(255,255,255,0.08);
    border-left: none;
    border-radius: 0 8px 8px 0;
    display: flex;
    flex-direction: column;
    transform: translateX(-20px);
    opacity: 0;
    pointer-events: none;
    transition: transform 0.3s cubic-bezier(0.4, 0, 0.2, 1), opacity 0.3s;
    z-index: -1;
    box-shadow: 4px 0 24px rgba(0,0,0,0.6);
}
.gp-drawer.gp-drawer-open {
    transform: translateX(0);
    opacity: 1;
    pointer-events: auto;
}
.gp-drawer-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 12px 16px;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    flex-shrink: 0;
}
.gp-drawer-title {
    font-weight: 600;
    font-size: 13px;
    color: #fff;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-family: 'Consolas', monospace;
}
.gp-drawer-close {
    background: none;
    border: none;
    color: #888;
    font-size: 18px;
    cursor: pointer;
    line-height: 1;
    padding: 0 4px;
}
.gp-drawer-close:hover {
    color: #fff;
}
.gp-drawer-body {
    flex: 1;
    overflow-y: auto;
    padding: 12px 16px;
    display: flex;
    flex-direction: column;
}

/* Data Detail Sub Tabs */
.gp-drawer-tabs {
    display: flex;
    overflow-x: auto;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    padding: 0 16px;
    flex-shrink: 0;
}
.gp-drawer-tab {
    background: none;
    border: none;
    color: #888;
    font-size: 11px;
    padding: 8px 12px;
    cursor: pointer;
    border-bottom: 2px solid transparent;
}
.gp-drawer-tab:hover { color: #ccc; }
.gp-drawer-tab.gp-active { color: #fff; border-bottom-color: #4a9eff; }

/* Tree View */
.gp-tree {
    font-family: 'Consolas', monospace;
    font-size: 12px;
    line-height: 1.6;
    user-select: text;
}
.gp-tree-node {
    padding-left: 14px;
    position: relative;
}
.gp-tree-caret {
    cursor: pointer;
    user-select: none;
    color: #888;
    font-size: 10px;
    position: absolute;
    left: 0;
    top: 3px;
    transition: transform 0.1s;
}
.gp-tree-caret:hover { color: #ccc; }
.gp-tree-caret.gp-collapsed { transform: rotate(-90deg); }
.gp-tree-key { color: #9cdcfe; margin-right: 4px; }
.gp-tree-val-str { color: #ce9178; }
.gp-tree-val-num { color: #b5cea8; }
.gp-tree-val-bool { color: #569cd6; }
.gp-tree-val-null { color: #888; }
.gp-tree-collapsed-text { color: #666; font-style: italic; cursor: pointer; }
.gp-tree-edit-input {
    background: rgba(0,0,0,0.5);
    border: 1px solid #4a9eff;
    color: #fff;
    font-family: inherit;
    font-size: inherit;
    padding: 0 2px;
    outline: none;
    width: auto;
    min-width: 40px;
}
/* Diff View */
.gp-diff-container {
    display: flex;
    flex-direction: column;
    gap: 8px;
    font-family: 'Consolas', monospace;
    font-size: 11px;
}
.gp-diff-row {
    display: flex;
    gap: 8px;
}
.gp-diff-col {
    flex: 1;
    min-width: 0;
    background: rgba(0,0,0,0.3);
    border-radius: 4px;
    padding: 8px;
    overflow-x: auto;
}
.gp-diff-col-title {
    color: #888;
    font-size: 10px;
    margin-bottom: 4px;
    text-transform: uppercase;
}
.gp-diff-line { white-space: pre; line-height: 1.4; display: flex; }
.gp-diff-add { background: rgba(76,175,80,0.15); color: #81c784; }
.gp-diff-sub { background: rgba(244,67,54,0.15); color: #e57373; }
.gp-diff-mod { background: rgba(255,152,0,0.15); color: #ffb74d; }

.gp-textarea-edit {
    width: 100%;
    flex: 1;
    min-height: 200px;
    background: rgba(0,0,0,0.3);
    border: 1px solid rgba(255,255,255,0.1);
    color: #e0e0e0;
    font-family: 'Consolas', monospace;
    font-size: 12px;
    padding: 8px;
    outline: none;
    resize: vertical;
    white-space: pre;
    tab-size: 2;
}
.gp-textarea-edit:focus { border-color: rgba(74,158,255,0.5); }

.gp-toolbar {
    display: flex;
    flex-direction: column;
    gap: 10px;
    padding: 10px 12px;
    margin-bottom: 12px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.05);
}
.gp-toolbar-controls {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.gp-toolbar-actions {
    margin-top: 2px;
}
.gp-toolbar-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    align-items: center;
}
.gp-data-item {
    align-items: flex-start;
}
.gp-data-item-main {
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 0;
    flex: 1;
}
.gp-data-item-title {
    font-size: 12px;
}
.gp-data-item-meta {
    white-space: normal;
    overflow-wrap: anywhere;
}
.gp-data-item-modified {
    border-left: 3px solid rgba(255, 180, 60, 0.7);
    padding-left: 9px;
}
.gp-data-load-more {
    justify-content: center;
    cursor: pointer;
}
.gp-empty-state {
    padding: 16px;
}
.gp-log-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    margin-bottom: 8px;
}
.gp-log-title-group {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
}
.gp-log-title {
    font-size: 11px;
    font-weight: 600;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.8px;
}
.gp-inline-actions {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
}
.gp-log-list {
    max-height: clamp(280px, 58vh, 560px);
}
.gp-log-entry {
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
}
.gp-log-entry-top {
    display: flex;
    align-items: center;
    gap: 6px;
    width: 100%;
    min-width: 0;
}
.gp-log-entry-time {
    margin-left: auto;
    font-size: 10px;
}
.gp-log-entry-message {
    font-size: 11px;
    word-break: break-word;
    padding-left: 4px;
    width: 100%;
}
.gp-cloud-compare {
    max-height: 240px;
    white-space: pre-wrap;
    word-break: break-word;
}

.gp-btn:focus-visible,
.gp-tab:focus-visible,
.gp-close-btn:focus-visible,
.gp-footer-update-hot:focus-visible,
.gp-footer-refresh:focus-visible,
.gp-section-title:focus-visible,
.gp-toggle:focus-visible,
.gp-select:focus-visible,
.gp-input:focus-visible,
.gp-search:focus-visible,
.gp-drawer-tab:focus-visible,
.gp-drawer-close:focus-visible,
.gp-textarea-edit:focus-visible {
    outline: 2px solid rgba(74,158,255,0.7);
    outline-offset: 2px;
}

/* ===== Performance Tab ===== */
.gp-perf-shell {
    display: flex;
    flex-direction: column;
    gap: 12px;
}
.gp-perf-hero {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 12px;
    padding: 12px;
    border-radius: 8px;
    background: rgba(255,255,255,0.035);
    border: 1px solid rgba(255,255,255,0.07);
    box-shadow: inset 3px 0 0 rgba(74,158,255,0.36);
}
.gp-perf-hero-main {
    min-width: 0;
}
.gp-perf-title-row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
}
.gp-perf-title {
    font-size: 11px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.8px;
    color: #8da1bb;
}
.gp-perf-hero-fps-row {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin-top: 8px;
}
.gp-perf-hero-fps {
    font-family: var(--gp-font-mono);
    font-size: 34px;
    line-height: 1;
    font-weight: 700;
    color: #f1f5f9;
}
.gp-perf-hero-unit {
    font-size: 12px;
    color: #4a9eff;
    font-weight: 700;
}
.gp-perf-hero-meta {
    margin-top: 7px;
    color: #9aa5b7;
    font-size: 11px;
    line-height: 1.45;
}
.gp-perf-actions {
    display: flex;
    flex-direction: column;
    gap: 7px;
    min-width: 0;
}
.gp-perf-actions .gp-btn-row {
    flex-wrap: wrap;
}
.gp-perf-actions .gp-btn:disabled {
    opacity: 0.55;
    cursor: default;
}
.gp-perf-sample-status {
    color: #7c879a;
    font-size: 11px;
    line-height: 1.45;
}
.gp-perf-metric-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
}
.gp-perf-metric {
    min-height: 86px;
    padding: 10px;
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
    border: 1px solid rgba(255,255,255,0.06);
    box-sizing: border-box;
}
.gp-perf-metric-label {
    color: #8d98aa;
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    font-weight: 700;
    min-height: 14px;
}
.gp-perf-metric-value {
    margin-top: 8px;
    font-family: var(--gp-font-mono);
    color: #f1f5f9;
    font-size: 22px;
    line-height: 1.05;
    font-weight: 700;
    word-break: break-word;
}
.gp-perf-metric-meta {
    margin-top: 7px;
    color: #7d8798;
    font-size: 11px;
    line-height: 1.35;
}
.gp-perf-good {
    border-color: rgba(76,175,80,0.24);
}
.gp-perf-good .gp-perf-metric-value {
    color: #94e2a0;
}
.gp-perf-warn {
    border-color: rgba(245,158,11,0.3);
}
.gp-perf-warn .gp-perf-metric-value {
    color: #fbbf24;
}
.gp-perf-bad {
    border-color: rgba(244,67,54,0.34);
}
.gp-perf-bad .gp-perf-metric-value {
    color: #fb7185;
}
.gp-perf-neutral {
    border-color: rgba(148,163,184,0.16);
}
.gp-perf-two-col,
.gp-perf-detail-grid {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 8px;
}
.gp-perf-panel {
    padding: 10px;
    border-radius: 8px;
    background: rgba(255,255,255,0.028);
    border: 1px solid rgba(255,255,255,0.055);
    min-width: 0;
}
.gp-perf-panel-title {
    color: #888;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.6px;
    margin-bottom: 9px;
}
.gp-perf-chart-wrap {
    min-width: 0;
}
.gp-perf-chart {
    width: 100%;
    height: 112px;
    display: block;
}
.gp-perf-chart-bg {
    fill: rgba(0,0,0,0.28);
    stroke: rgba(255,255,255,0.08);
}
.gp-perf-chart-grid {
    stroke: rgba(148,163,184,0.14);
    stroke-width: 1;
}
.gp-perf-chart-budget {
    stroke: rgba(245,158,11,0.8);
    stroke-width: 1.5;
    stroke-dasharray: 5 4;
}
.gp-perf-chart-line {
    fill: none;
    stroke: #4a9eff;
    stroke-width: 2.4;
    stroke-linejoin: round;
    stroke-linecap: round;
}
.gp-perf-chart-empty {
    fill: #64748b;
    font-size: 11px;
    font-family: var(--gp-font-ui);
}
.gp-perf-chart-legend {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    color: #758195;
    font-size: 10px;
    line-height: 1.35;
    margin-top: 6px;
}
.gp-perf-bars {
    display: flex;
    flex-direction: column;
    gap: 9px;
}
.gp-perf-bar-top {
    display: flex;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 4px;
    color: #a8b2c2;
    font-size: 11px;
}
.gp-perf-bar-track {
    height: 8px;
    border-radius: 999px;
    background: rgba(0,0,0,0.3);
    border: 1px solid rgba(148,163,184,0.12);
    overflow: hidden;
}
.gp-perf-bar-fill {
    height: 100%;
    min-width: 2px;
    border-radius: 999px;
    background: #4a9eff;
}
.gp-perf-kv {
    display: flex;
    flex-direction: column;
    gap: 5px;
}
.gp-perf-kv-row {
    display: grid;
    grid-template-columns: minmax(96px, 0.8fr) minmax(0, 1.2fr);
    gap: 8px;
    align-items: start;
    min-width: 0;
    font-size: 11px;
    line-height: 1.35;
}
.gp-perf-kv-label {
    color: #738096;
}
.gp-perf-kv-value {
    min-width: 0;
    color: #cbd5e1;
    text-align: right;
    overflow-wrap: anywhere;
    display: flex;
    justify-content: flex-end;
    align-items: center;
    gap: 6px;
}
.gp-perf-report {
    display: flex;
    flex-direction: column;
    gap: 8px;
}
.gp-perf-report-summary {
    display: flex;
    gap: 7px;
    align-items: center;
    flex-wrap: wrap;
}

@media (max-width: 1040px) {
    .gp-drawer {
        top: 8px;
        left: 8px;
        right: 8px;
        width: auto;
        min-width: 0;
        max-width: none;
        height: calc(100% - 16px);
        border-left: 1px solid rgba(255,255,255,0.08);
        border-radius: 8px;
        transform: translateY(12px);
    }
    .gp-drawer.gp-drawer-open {
        transform: translateY(0);
    }
    .gp-diff-row {
        flex-direction: column;
    }
}

@media (max-width: 760px) {
    #gp-overlay {
        width: 100vw;
    }
    .gp-header,
    .gp-content,
    .gp-drawer-header,
    .gp-drawer-body {
        padding-left: 12px;
        padding-right: 12px;
    }
    .gp-tab {
        padding: 8px 10px;
    }
    .gp-footer {
        flex-direction: column;
        align-items: flex-start;
    }
    .gp-footer-right {
        width: 100%;
        justify-content: space-between;
    }
    .gp-input-wrap,
    .gp-select-wrap {
        flex-direction: column;
        align-items: stretch;
        gap: 6px;
    }
    .gp-input-label,
    .gp-select-label {
        min-width: 0;
        white-space: normal;
    }
    .gp-btn-row .gp-btn {
        flex: 1 1 136px;
    }
    .gp-log-toolbar {
        flex-direction: column;
        align-items: stretch;
    }
    .gp-log-title-group {
        flex-wrap: wrap;
    }
    .gp-perf-metric-grid {
        grid-template-columns: 1fr;
    }
    .gp-perf-kv-row {
        grid-template-columns: 1fr;
        gap: 2px;
    }
    .gp-perf-kv-value {
        text-align: left;
        justify-content: flex-start;
    }
    .gp-pack-card {
        grid-template-columns: 44px minmax(0, 1fr);
    }
    .gp-pack-name-row {
        flex-direction: column;
        align-items: stretch;
    }
    .gp-pack-ctrl {
        grid-column: 2;
        flex-direction: row;
        flex-wrap: wrap;
    }
}

@media (prefers-reduced-motion: reduce) {
    #gp-overlay,
    .gp-drawer,
    .gp-tab,
    .gp-btn,
    .gp-toggle,
    .gp-toggle-knob,
    .gp-section-arrow,
    .gp-footer-refresh,
    .gp-perf-chart-line {
        transition: none !important;
        animation: none !important;
    }
}

`,f=new e(`overlay`),p=null,m=null,h=null,g=null,_=null,v=null,y=!1,b=null,x=[],S=``,C={status:`idle`,latestVersion:``,error:``},w={onCheck:null,onOpen:null},T=n(a().overlayHotkey,o),E=[],D=null;function O(){let e=document.createElement(`style`);e.id=`gp-next-styles`,e.textContent=d,document.head.appendChild(e)}function k(){p=document.createElement(`div`),p.id=`gp-overlay`;let e=document.createElement(`div`);e.className=`gp-header`;let t=document.createElement(`span`);t.className=`gp-logo`,t.textContent=`GP Next`,g=document.createElement(`span`),g.className=`gp-status`,g.textContent=s(`header.status.waiting`);let n=document.createElement(`button`);n.className=`gp-close-btn`,n.innerHTML=`&times;`,n.addEventListener(`click`,B),e.appendChild(t),e.appendChild(g),e.appendChild(n),m=document.createElement(`div`),m.className=`gp-tabs`,m.id=`gp-tab-bar`,h=document.createElement(`div`),h.className=`gp-content`,h.id=`gp-content`,_=document.createElement(`div`),_.className=`gp-footer`,p.appendChild(e),p.appendChild(m),p.appendChild(h),p.appendChild(_),document.body.appendChild(p),v=document.createElement(`div`),v.className=`gp-f1-hint`,v.addEventListener(`click`,V),document.body.appendChild(v),I()}function A(){if(!_)return;_.innerHTML=``;let e=document.createElement(`span`);e.className=`gp-footer-version`,e.textContent=s(`footer.version`,S||`?`),_.appendChild(e);let t=document.createElement(`div`);t.className=`gp-footer-right`;let n=document.createElement(`button`);n.type=`button`,n.className=`gp-footer-update`,n.disabled=C.status!==`update-available`,C.status===`update-available`?(n.classList.add(`gp-footer-update-hot`),n.textContent=s(`footer.updateAvailable`,C.latestVersion||`?`),n.title=s(`footer.openDownload`),n.addEventListener(`click`,()=>{w.onOpen&&w.onOpen()})):C.status===`checking`?n.textContent=s(`footer.updateChecking`):C.status===`up-to-date`?n.textContent=s(`footer.upToDate`):C.status===`error`?(n.textContent=s(`footer.updateCheckFailed`),n.title=C.error||s(`footer.updateCheckFailed`)):n.textContent=s(`footer.updateIdle`),t.appendChild(n);let r=document.createElement(`button`);r.type=`button`,r.className=`gp-footer-refresh`,r.textContent=`↻`,r.title=s(`footer.checkNow`),C.status===`checking`&&(r.disabled=!0,r.classList.add(`gp-spinning`)),r.addEventListener(`click`,()=>{w.onCheck&&w.onCheck()}),t.appendChild(r),_.appendChild(t)}function j(){document.addEventListener(`keydown`,e=>{if(F(e)&&r(T,e)){e.preventDefault(),e.stopPropagation(),V();return}e.key===`Escape`&&y&&(e.preventDefault(),e.stopPropagation(),B())},!0)}function M(e){let t=document.getElementById(`GameCanvas`)||document.querySelector(`canvas`);t&&(t.style.pointerEvents=e?`none`:``)}function N(){m.innerHTML=``;for(let e of E){let t=document.createElement(`button`);t.type=`button`,t.className=`gp-tab`+(e.id===D?` gp-tab-active`:``),t.textContent=s(e.labelKey),t.dataset.tabId=e.id,t.addEventListener(`click`,()=>Z(e.id)),m.appendChild(t)}}function P(e){return!e||typeof e.closest!=`function`||e.closest(`[data-gp-hotkey-recorder="true"]`)?!1:!!e.closest(`input, textarea, select, [contenteditable="true"], [contenteditable=""]`)}function F(e){return!(!e||P(e.target)&&!i(T))}function I(){if(!v)return;let e=t(T);v.textContent=e,v.title=s(`header.hotkeyTitle`,e)}function L(){h.innerHTML=``;let e=E.find(e=>e.id===D);if(e&&e.render)try{e.render(h)}catch(t){f.error(`Tab '${e.id}' render failed: ${t?.stack||t}`),h.innerHTML=``;let n=document.createElement(`div`);n.className=`gp-text-muted`,n.textContent=`${s(`common.failed`)}: ${String(t?.message||t)}`,h.appendChild(n)}}function R(e,t){if(typeof e?.[t]==`function`)try{Promise.resolve(e[t]()).catch(n=>{f.error(`Tab '${e.id}' ${t} failed: ${n?.stack||n}`)})}catch(n){f.error(`Tab '${e.id}' ${t} failed: ${n?.stack||n}`)}}function z(){p&&(c(),y=!0,p.classList.add(`gp-open`),v.classList.add(`gp-hidden`),M(!0),L(),R(E.find(e=>e.id===D),`onActivate`))}function B(){if(p){y=!1,p.classList.remove(`gp-open`),v.classList.remove(`gp-hidden`),M(!1);try{u()}catch{}R(E.find(e=>e.id===D),`onDeactivate`)}}function V(){y?B():z()}function H(){return y}function U(e){b=null,x=[],g&&(g.textContent=e)}function W(e,...t){b=e,x=t,g&&(g.textContent=s(e,...t))}function G(e){S=String(e||``),A()}function K(e){T=n(e,o),I()}function q(){return{...T}}function J(e){C={...C,...e||{}},A()}function Y(e={}){w={onCheck:typeof e.onCheck==`function`?e.onCheck:null,onOpen:typeof e.onOpen==`function`?e.onOpen:null},A()}function X(e){let t=E.findIndex(t=>t.id===e.id),n=t!==-1&&D===e.id;t===-1?E.push(e):E[t]=e,m&&(N(),D?n&&(L(),R(E.find(e=>e.id===D),`onActivate`)):Z(e.id))}function Z(e){let t=E.find(t=>t.id===e);if(!t||D===e&&h.children.length>0)return;R(E.find(e=>e.id===D),`onDeactivate`),D=e,m.querySelectorAll(`.gp-tab`).forEach(t=>{t.classList.toggle(`gp-tab-active`,t.dataset.tabId===e)});let n=m.querySelector(`.gp-tab[data-tab-id="${e}"]`);n?.scrollIntoView&&n.scrollIntoView({block:`nearest`,inline:`nearest`}),L(),R(t,`onActivate`)}function Q(){return O(),k(),j(),l(()=>{N(),D&&L(),I(),b&&g&&(g.textContent=s(b,...x)),A()}),A(),{show:z,hide:B,toggle:V,isOpen:H,updateStatus:U,updateStatusKey:W,setVersion:G,setHotkey:K,getHotkey:q,setUpdateState:J,bindUpdateActions:Y,registerTab:X,switchTab:Z}}export{z as a,K as i,Q as n,H as r,B as t};