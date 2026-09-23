// Disk accounting for the DISK metric.
//
// Why the KSystemStats "disk/all/*" sensors are not used here: ksystemstats
// builds one volume object per Solid storage volume and then sums their values.
// A LUKS container and the filesystem on it are two Solid volumes backed by one
// filesystem, so that filesystem is counted twice. On a LUKS + btrfs machine
// "All Disks" reports 948.7 GiB for a 474.3 GiB disk, and the used amount is
// doubled with it. In plasma/ksystemstats plugins/disks/disks.cpp,
// createAccessibleVolumeObject() drops a volume only when another volume
// already claims the same mount point, while the rawDisk branch (usage
// Encrypted or Raid) inserts its volume directly and skips that check
// altogether.
//
// findmnt prints the kernel's mount table, in which every mount appears once,
// so the widget does its own accounting from it:
//
//   * only mounts on a block device are counted, which leaves out network
//     shares, tmpfs and overlay filesystems;
//   * mounts that share a backing device (btrfs subvolumes, bind mounts)
//     collapse into one entry, so capacity is never counted twice;
//   * all other local filesystems are summed, including a /home or a data disk
//     of its own.
//
// The rule for "used" is capacity minus the space still available to the user
// (statvfs f_bavail, which is also what KSystemStats uses for its percentage),
// so used + free always adds up to total. GNU df's "used" column is a little
// smaller because it counts the btrfs metadata reserve as free.

// The device behind a mount. A btrfs subvolume mount carries the subvolume in
// brackets ("/dev/sda2[/root]"), so the brackets are stripped to give the
// device whose space is really being reported.
function deviceKey(source) {
    return String(source).replace(/\[[^\]]*\]$/, "");
}

// Parse the output of:
//   findmnt -J -b -l -o SOURCE,TARGET,FSTYPE,SIZE,AVAIL
// (-b = bytes, -l = flat list, -J = JSON)
// Returns one row per distinct local filesystem, ordered by mount point.
// Unusable or empty input gives an empty list, never an exception.
function filesystems(jsonText) {
    let parsed;
    try {
        parsed = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!parsed || !Array.isArray(parsed.filesystems)) {
        return [];
    }

    const seen = {};
    const rows = [];
    for (let i = 0; i < parsed.filesystems.length; ++i) {
        const entry = parsed.filesystems[i];
        if (!entry || typeof entry.source !== "string"
            || entry.source.indexOf("/dev/") !== 0) {
            continue;                       // not on a block device
        }
        const key = deviceKey(entry.source);
        if (seen[key]) {
            continue;                       // same device, mounted again
        }
        const size = Number(entry.size);
        const avail = Number(entry.avail);
        if (!isFinite(size) || size <= 0 || !isFinite(avail)) {
            continue;                       // no usable capacity reading
        }
        seen[key] = true;
        const used = Math.max(0, size - avail);
        rows.push({
            device: key,
            target: typeof entry.target === "string" ? entry.target : key,
            fstype: typeof entry.fstype === "string" ? entry.fstype : "",
            total: size,
            free: avail,
            used: used,
            percent: used * 100 / size
        });
    }

    rows.sort(function (a, b) {
        return a.target < b.target ? -1 : a.target > b.target ? 1 : 0;
    });
    return rows;
}

// Sum over the counted filesystems. Shape:
//   { total, used, free, percent, filesystems: [ ... ] }
// total is 0 when nothing could be read, which the widget treats as "no
// values" instead of "0 bytes used".
function report(jsonText) {
    const rows = filesystems(jsonText);

    let total = 0;
    let free = 0;
    for (let i = 0; i < rows.length; ++i) {
        total += rows[i].total;
        free += rows[i].free;
    }
    const used = total - free;

    return {
        total: total,
        used: used,
        free: free,
        percent: total > 0 ? used * 100 / total : 0,
        filesystems: rows
    };
}

// Byte values as KSystemStats prints them elsewhere in the widget: binary
// units, one decimal ("474.3 GiB", "598.8 MiB"). Whole bytes get no decimal.
function formatBytes(bytes) {
    const units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    const value = Number(bytes);
    if (!isFinite(value) || value < 0) {
        return "—";
    }

    let scaled = value;
    let unit = 0;
    while (scaled >= 1024 && unit < units.length - 1) {
        scaled /= 1024;
        ++unit;
    }
    return (unit === 0 ? String(Math.round(scaled)) : scaled.toFixed(1))
           + " " + units[unit];
}
