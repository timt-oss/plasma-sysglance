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
// The numbers come from lsblk instead:
//
//     lsblk -J -b -o NAME,PKNAME,MOUNTPOINTS,FSSIZE,FSAVAIL
//
// lsblk reports the kernel's mount table with the same sizes as `df -B1`, and
// it reports the device tree as well, which the second rule below needs.
//
//   * a row is a mounted filesystem when it has both a mount point and a
//     filesystem size. A LUKS container, swap and unformatted disks have
//     neither, so they drop out on their own and nothing is counted twice;
//   * a filesystem is left out when it is mounted inside another filesystem on
//     the same drive and that other filesystem is at least as large. /boot and
//     the EFI system partition sit inside the root filesystem on the same drive
//     and drop out, so the total is not inflated by them; a data partition
//     larger than its root filesystem — and any filesystem on a further drive —
//     still counts;
//   * used is capacity minus the space still available to the user (statvfs
//     f_bavail, the basis KSystemStats uses for its percentage), so used + free
//     always adds up to total. GNU df's "used" column is a little smaller,
//     because it counts the btrfs metadata reserve as free.

// Every node of the block-device tree, in tree order.
function flatten(nodes, out) {
    for (let i = 0; i < nodes.length; ++i) {
        const node = nodes[i];
        if (!node || typeof node.name !== "string") {
            continue;
        }
        out.push(node);
        if (Array.isArray(node.children)) {
            flatten(node.children, out);
        }
    }
    return out;
}

// The drive a device belongs to: the topmost device above it. A partition
// answers its disk, a LUKS or LVM mapping answers the disk under its container,
// and a whole disk answers itself.
function driveOf(name, parents) {
    let drive = name;
    let parent = parents[drive];
    let guard = 0;
    while (parent && guard++ < 16) {
        drive = parent;
        parent = parents[drive];
    }
    return drive;
}

// True when one of `targets` sits below one of `ancestors`.
function isInside(targets, ancestors) {
    for (let i = 0; i < targets.length; ++i) {
        for (let j = 0; j < ancestors.length; ++j) {
            if (targets[i] === ancestors[j]) {
                continue;
            }
            const prefix = ancestors[j] === "/" ? "/" : ancestors[j] + "/";
            if (targets[i].indexOf(prefix) === 0) {
                return true;
            }
        }
    }
    return false;
}

// Parse the lsblk JSON and return the rows that count, ordered by mount point.
// Unusable or empty input gives an empty list, never an exception.
function filesystems(jsonText) {
    let parsed;
    try {
        parsed = JSON.parse(jsonText);
    } catch (e) {
        return [];
    }
    if (!parsed || !Array.isArray(parsed.blockdevices)) {
        return [];
    }

    const nodes = flatten(parsed.blockdevices, []);
    const parents = {};
    for (let i = 0; i < nodes.length; ++i) {
        if (typeof nodes[i].pkname === "string" && nodes[i].pkname !== "") {
            parents[nodes[i].name] = nodes[i].pkname;
        }
    }

    const mounted = [];
    for (let i = 0; i < nodes.length; ++i) {
        const node = nodes[i];
        // "[SWAP]" is a mount point as far as lsblk is concerned; only real
        // paths count.
        const targets = (Array.isArray(node.mountpoints) ? node.mountpoints : [])
            .filter(mount => typeof mount === "string" && mount.charAt(0) === "/");
        const total = Number(node.fssize);
        const free = Number(node.fsavail);
        if (targets.length === 0 || !isFinite(total) || total <= 0 || !isFinite(free)) {
            continue;
        }

        // Several mount points on one device (btrfs subvolumes) are one row;
        // the shortest path is what the popup names it by.
        let name = targets[0];
        for (let t = 1; t < targets.length; ++t) {
            if (targets[t].length < name.length) {
                name = targets[t];
            }
        }

        const used = Math.max(0, total - free);
        mounted.push({
            device: node.name,
            drive: driveOf(node.name, parents),
            targets: targets,
            name: name,
            total: total,
            free: free,
            used: used,
            percent: used * 100 / total
        });
    }

    // Drop the smaller of two filesystems where one is mounted inside the other
    // on the same drive.
    const kept = [];
    for (let i = 0; i < mounted.length; ++i) {
        const row = mounted[i];
        const covered = mounted.some(other => other !== row
            && other.drive === row.drive
            && other.total >= row.total
            && isInside(row.targets, other.targets));
        if (!covered) {
            kept.push(row);
        }
    }

    kept.sort(function (a, b) {
        return a.name < b.name ? -1 : a.name > b.name ? 1 : 0;
    });
    return kept;
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
