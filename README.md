# System Glance

A compact KDE Plasma 6 panel widget that replaces a whole row of system-monitor
plasmoids with one labeled strip:

```
RAM 19% | DISK 48% | CPU 1% 39° | GPU 2% 43° | FAN 2520 RPM
```

## Features

- **One strip instead of a row of widgets** — RAM used %, disk used %, CPU usage
  % with hottest-core temperature, GPU usage % and temperature, and fan speed if
  you want it. Fixed-width digits, so the strip does not jump as values tick.
- **Popup on click, tooltip on hover** — the popup shows memory and swap, each
  filesystem, every CPU core, and the GPU's load, VRAM, power draw, clocks and
  temperature peak.
- **Alert colors** — a value turns amber at the threshold you set and red ten
  above it. A nearly-full disk only ever turns amber.
- **Optional desktop notifications** — off by default, one switch per threshold:
  a notification when a value crosses into the worse state, not while it stays
  there.
- **Make it yours** — the Appearance page sets the order of the metrics, which
  values each shows, labels and icons, font size, gaps, width and colors, and the
  thresholds and update interval. Defaults follow the Plasma theme.
- **Fan speed is optional** — pick your sensor on the Appearance page; the metric
  appears once you have.
- Reads the same sensor daemon as Plasma's own system monitor, so NVIDIA cards
  work without lm_sensors setup.

## Install

```sh
make install    # first time
make upgrade    # after changes (restarts plasmashell)
```

Then add **System Glance** to a panel via *Add Widgets…*. Plasma 6 and `lsblk`
are all it needs — both stock — and NVIDIA stats need a working `nvidia-smi`.

## Disk values

The disk percentage counts each mounted filesystem once, from the kernel's mount
table, so containers, swap and `/boot` do not inflate it. The sensor daemon's own
"All Disks" figure can: a LUKS container and the filesystem inside it are summed
as two, which reports about twice the real capacity. GNU `df`'s *used* column
reads a little smaller than ours on btrfs. The rules are in
`contents/ui/diskusage.js`.

## License

MIT
