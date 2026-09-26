# Changelog

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and versions follow the `Version` field in `metadata.json` (tag `v<version>`).

## [3.0] - 2026-09-26

### Added
- Per-alert desktop notifications, off by default. The General settings page gets
  a "Notify" switch beside each alert threshold; a notification is sent when the
  value crosses into a worse state — amber at the threshold, red at the critical
  level (`threshold + 10`, or the fan's own critical RPM) — rather than on every
  update. The same state is not announced twice inside five minutes, an
  escalation to red always is, and a switch turned on while a value is already
  over its threshold announces it once at that moment. Disk never goes red, so
  its switch only ever warns. The first reading after the widget loads is a
  baseline: values that are already over their thresholds when a login reloads
  the widget are not announced, since that is a level and not a crossing.
- Fan speed as a fifth metric. The Appearance settings page lists the RPM
  sensors KSystemStats publishes (typically one `lmsensors/<chip>/fanN` sensor
  per fan through lm_sensors) and the picked one is shown in the strip. The
  metric stays hidden until a sensor is chosen, since the sensor IDs are
  machine-specific. Fan speed carries its own warning and critical RPM
  thresholds: the shared "threshold + 10" step does not fit RPM.

### Fixed
- Reordering the metric rows on the Appearance settings page did nothing. The
  drag handle was given the ListView's delegate itself, and it reparents
  whatever it is handed to the ListView, so a drag never moved a row.
- Disk amounts no longer come from KSystemStats' `disk/all/*` sensors, which
  count one filesystem twice when Solid lists both a LUKS container and the
  filesystem on it — the total read as about twice the real capacity, with the
  used amount doubled. They are read from the kernel's device tree (`lsblk`)
  instead, so the *All disks* line, the tooltip and the popup now agree with
  `df`.
- The popup's per-filesystem list is built from that read, which removes the
  hardcoded partition UUIDs of the machine the widget was written on.

### Changed
- The DISK metric leaves out a filesystem that is mounted inside another
  filesystem on the same drive when that other one is at least as large, so
  `/boot` and the EFI system partition no longer inflate the total. A data
  partition larger than its root filesystem, and any filesystem on a further
  drive, still counts. A LUKS container, swap and unformatted disks have no
  mount point and drop out.
- Plugin ID renamed from `com.nerdstrike.sysglance` to `com.timtoss.sysglance`, so
  this fork no longer installs over the original product. Settings do not carry
  over on an in-place upgrade: remove the old widget and add this one.

## [2.2] - 2026-07-15

### Changed
- Plugin ID renamed from `com.renato.sysglance` to `com.nerdstrike.sysglance`
  (reverse-DNS of an owned domain). Existing users must remove and re-add the
  widget; per-widget settings from an in-place upgrade are not carried over.

## [2.1] - 2026-07-15

### Added
- "Restore Defaults" action in each settings page's title bar.

### Changed
- Color pickers now always show the effective color (the theme's until you
  pick one), with an undo button to return a picked color to the theme —
  replacing the per-color "Custom" checkboxes.

## [2.0] - 2026-07-15

### Added
- Appearance settings page with a live preview of the panel strip driven by
  the actual configuration (sample sensor values).
- Reorderable metric list: drag to set strip order, checkbox to show/hide,
  per-metric dropdown for which values are shown and in what order.
- Custom format templates per metric (`Custom…`) with `{variable}`
  placeholders and click-to-insert chips documenting each variable.
- Text or icon labels; both label text and icons are configurable per metric
  (icons via KDE's icon dialog, including custom PNG/SVG files).
- Font family (lazy-loaded list) and font size (editable preset combo).
- Value width: fit content (default) or a fixed pixel width for all slots.
- Configurable gaps inside groups and between groups.
- Separators can be hidden; separator color is independent.
- Per-color theme overrides (values, labels, separators, warning, critical) —
  each independently follows the Plasma theme unless set to custom.

### Changed
- Values in the strip are right-aligned within fixed slots.
- Config dialog forms hug the left edge instead of KDE's centered layout.
- `qmllint` now actually runs in `make lint` (the `--bare` flag was invalid
  and silently masked by `|| true`).

### Removed
- Bitmask display-mode config keys (`<metric>Display`), replaced by
  `metricOrder` + `<metric>Shown`/`<metric>Parts`/`<metric>Format`.

## [1.1] - 2026-07-13

### Added
- Threshold color coding and click popup with per-core/per-partition detail.

## [1.0] - 2026-07-12

### Added
- Initial release: RAM/disk/CPU/GPU panel strip via KSystemStats.
