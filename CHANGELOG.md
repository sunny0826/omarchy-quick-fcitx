# Changelog

## 1.0.0 - 2026-09-24

- Bar widget showing 中/en with live D-Bus updates and optically centered label
- Left-Shift tap toggles Chinese/English (marker-managed, opt-in block in bindings.lua)
- Management panel: manual 中/英 switch, fcitx5 restart that blocks until ready,
  input-method list edits (stop → edit → start → D-Bus verify with automatic
  rollback), engine install in a visible terminal, Rime schema import
- Addable input methods filtered by fcitx5's own loadable set
- Scrollable panel content, collapsed install section, no explanatory clutter
-105 unit-test assertions + GitHub Actions CI
