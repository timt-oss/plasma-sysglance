import QtQuick
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.notification

import "alerts.js" as Alerts
import "diskusage.js" as DiskUsage

PlasmoidItem {
    id: root

    preferredRepresentation: compactRepresentation

    readonly property int rateMs: Plasmoid.configuration.updateInterval * 1000

    // --- Disk accounting ----------------------------------------------------
    //
    // The DISK metric deliberately does not read KSystemStats' disk/all/*
    // sensors. That aggregate gives one volume object to a LUKS container and
    // another to the filesystem on it whenever Solid lists both, so a single
    // filesystem is counted twice: on a LUKS + btrfs machine the strip claims
    // 948.7 GiB for a 474.3 GiB disk, with the used amount doubled too.
    // lsblk reports the kernel's own device tree and mount table, where a
    // filesystem appears once, so the numbers are built from that instead — see
    // contents/ui/diskusage.js for the rules, and for why the used amount is
    // capacity minus available.
    //
    // diskUsage stays null until the first read arrives, so an unreachable
    // lsblk shows "—" rather than a plausible-looking 0%.
    property var diskUsage: null
    property string diskError: ""

    readonly property bool diskKnown: root.diskUsage !== null

    // Capacity changes far more slowly than the strip's own interval, and every
    // read is a process, so disks refresh on their own 10 s floor.
    Timer {
        interval: Math.max(root.rateMs, 10000)
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshDisks()
    }

    P5Support.DataSource {
        id: diskExec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            root.readDisks(data && data["stdout"] ? data["stdout"] : "");
            disconnectSource(source);
        }
    }

    function refreshDisks() {
        if (diskExec.connectedSources.length > 0) {
            return;                            // one read in flight at a time
        }
        diskExec.connectSource("lsblk -J -b -o NAME,PKNAME,MOUNTPOINTS,FSSIZE,FSAVAIL");
    }

    function readDisks(stdout) {
        const read = DiskUsage.report(stdout);
        if (read.total <= 0) {
            // lsblk missing, or its output is not what we expect: keep the last
            // good values and say so in the popup.
            root.diskError = i18n("no readable device tree (lsblk)");
            return;
        }
        root.diskError = "";
        root.diskUsage = read;
    }

    // Disk values for the strip, tooltip and popup — "—" until the first read.
    function fmtBytes(bytes) { return DiskUsage.formatBytes(bytes); }
    function diskPercent() { return root.diskKnown ? pct(root.diskUsage.percent) : "—"; }
    function diskUsed()    { return root.diskKnown ? fmtBytes(root.diskUsage.used) : "—"; }
    function diskFree()    { return root.diskKnown ? fmtBytes(root.diskUsage.free) : "—"; }
    function diskTotal()   { return root.diskKnown ? fmtBytes(root.diskUsage.total) : "—"; }

    readonly property var diskFilesystems: root.diskKnown ? root.diskUsage.filesystems : []

    // Sensors used by the panel strip and tooltip — always subscribed.
    // Popup-only sensors live inside fullRepresentation so they are lazy.
    Sensors.Sensor { id: ramSensor;    sensorId: "memory/physical/usedPercent"; updateRateLimit: root.rateMs }
    Sensors.Sensor { id: ramUsed;      sensorId: "memory/physical/used";        updateRateLimit: root.rateMs }
    Sensors.Sensor { id: ramTotal;     sensorId: "memory/physical/total";       updateRateLimit: root.rateMs }
    Sensors.Sensor { id: ramFree;      sensorId: "memory/physical/free";        updateRateLimit: root.rateMs }
    Sensors.Sensor { id: cpuUsage;     sensorId: "cpu/all/usage";               updateRateLimit: root.rateMs }
    Sensors.Sensor { id: cpuTempAvg;   sensorId: "cpu/all/averageTemperature";  updateRateLimit: root.rateMs }
    Sensors.Sensor { id: cpuTempMax;   sensorId: "cpu/all/maximumTemperature";  updateRateLimit: root.rateMs }
    Sensors.Sensor { id: cpuCount;     sensorId: "cpu/all/cpuCount";            updateRateLimit: root.rateMs }
    Sensors.Sensor { id: gpuUsage;     sensorId: "gpu/gpu0/usage";              updateRateLimit: root.rateMs }
    Sensors.Sensor { id: gpuTemp;      sensorId: "gpu/gpu0/temperature";        updateRateLimit: root.rateMs }
    Sensors.Sensor { id: gpuPower;     sensorId: "gpu/gpu0/power";              updateRateLimit: root.rateMs }
    Sensors.Sensor { id: gpuVram;      sensorId: "gpu/gpu0/usedVram";           updateRateLimit: root.rateMs }
    Sensors.Sensor { id: gpuVramTotal; sensorId: "gpu/gpu0/totalVram";          updateRateLimit: root.rateMs }

    // The fan metric reads one KSystemStats RPM sensor. Its ID is
    // machine-specific, so the user picks it in the settings page and the
    // metric stays hidden until then. A Sensor with an empty ID would ask the
    // daemon to subscribe to nothing, so it is disabled instead.
    Sensors.Sensor {
        id: fanSensor
        enabled: root.fanConfigured
        sensorId: Plasmoid.configuration.fanSensorId
        // The daemon reports 0 until its first push, and every push after that
        // waits for updateRateLimit. On a 60 second interval that leaves the
        // strip showing "0 RPM" for a whole minute after login, so the fan
        // keeps a short limit of its own.
        updateRateLimit: Math.min(root.rateMs, 5000)
    }

    readonly property bool fanConfigured: Plasmoid.configuration.fanSensorId !== ""

    // NVIDIA exposes a single GPU temperature, so "peak" is a rolling
    // 10-minute maximum — it self-heals instead of staying red all day.
    property var gpuHistory: []
    readonly property real gpuPeak: gpuHistory.length > 0 ? Math.max(...gpuHistory) : -1

    Timer {
        interval: root.rateMs
        running: true
        repeat: true
        onTriggered: {
            const v = gpuTemp.value;
            if (v === undefined || isNaN(v) || v <= 0) {
                return;
            }
            const maxLen = Math.max(1, Math.round(600000 / root.rateMs));
            let h = root.gpuHistory.slice();
            h.push(v);
            if (h.length > maxLen) {
                h = h.slice(h.length - maxLen);
            }
            root.gpuHistory = h;
        }
    }

    // 0 = normal, 1 = warning (amber) at the configured threshold,
    // 2 = critical (red) at threshold + 10
    function tier(v, threshold) {
        if (v === undefined || isNaN(v)) {
            return 0;
        }
        if (v >= threshold + 10) {
            return 2;
        }
        return v >= threshold ? 1 : 0;
    }

    function tierColor(t) {
        return t === 2 ? root.critColor
             : t === 1 ? root.warnColor
             : root.valueColor;
    }

    function pct(v) {
        return (v === undefined || isNaN(v)) ? "—" : Math.round(v) + "%";
    }

    function deg(v) {
        return (v === undefined || isNaN(v) || v <= 0) ? "—" : Math.round(v) + "°";
    }

    function fmt(sensor) {
        const v = sensor.formattedValue;
        return (v === undefined || v === "") ? "—" : v;
    }

    // KSystemStats renders RPM as "2,520.0 RPM" — too wide and too precise for
    // a panel strip, so the fan formats its own number.
    function rpm(v) {
        return (v === undefined || isNaN(v)) ? "—" : Math.round(v) + " RPM";
    }

    function fanValue() {
        return root.fanConfigured ? fanSensor.value : undefined;
    }

    function fanName() {
        return root.fanConfigured && fanSensor.name !== "" ? fanSensor.name : "—";
    }

    // --- Panel strip content ---------------------------------------------
    // The strip renders visibleMetrics: metricOrder (left-to-right, drag to
    // reorder in settings) filtered to shown metrics, each with an ordered
    // list of parts — "usage" (percent), "temp" (temperature), "abs" (used
    // amount). Adding a metric or part = a branch in the helpers below plus
    // a row/combo entry in configAppearance.qml.
    readonly property var visibleMetrics: {
        const shown = {
            ram: Plasmoid.configuration.ramShown,
            disk: Plasmoid.configuration.diskShown,
            cpu: Plasmoid.configuration.cpuShown,
            gpu: Plasmoid.configuration.gpuShown,
            fan: Plasmoid.configuration.fanShown && root.fanConfigured
        };
        const parts = {
            ram: Plasmoid.configuration.ramParts,
            disk: Plasmoid.configuration.diskParts,
            cpu: Plasmoid.configuration.cpuParts,
            gpu: Plasmoid.configuration.gpuParts,
            fan: Plasmoid.configuration.fanParts
        };
        return Plasmoid.configuration.metricOrder.split(",")
            .map(k => k.trim())
            .filter(k => shown[k] !== undefined && shown[k] && parts[k] !== "")
            .map(k => ({ key: k, parts: parts[k].split(",") }));
    }

    function metricLabel(metric) {
        return metric === "ram" ? Plasmoid.configuration.ramLabel
             : metric === "disk" ? Plasmoid.configuration.diskLabel
             : metric === "cpu" ? Plasmoid.configuration.cpuLabel
             : metric === "gpu" ? Plasmoid.configuration.gpuLabel
             : Plasmoid.configuration.fanLabel;
    }

    function metricIcon(metric) {
        if (metric === "fan") {
            // Breeze ships no fan icon, so an empty setting falls back to the
            // SVG that comes with the widget.
            return Plasmoid.configuration.fanIcon !== ""
                ? Plasmoid.configuration.fanIcon
                : Qt.resolvedUrl("../images/fan.svg");
        }
        return metric === "ram" ? Plasmoid.configuration.ramIcon
             : metric === "disk" ? Plasmoid.configuration.diskIcon
             : metric === "cpu" ? Plasmoid.configuration.cpuIcon
             : Plasmoid.configuration.gpuIcon;
    }

    // Per-metric {variables} available to "custom" format templates
    function templateVars(metric) {
        if (metric === "ram") {
            return { usage: pct(ramSensor.value), used: fmt(ramUsed), free: fmt(ramFree), total: fmt(ramTotal) };
        }
        if (metric === "disk") {
            return { usage: diskPercent(), used: diskUsed(), free: diskFree(), total: diskTotal() };
        }
        if (metric === "cpu") {
            return { usage: pct(cpuUsage.value), temp: deg(cpuTempMax.value), tempavg: deg(cpuTempAvg.value) };
        }
        if (metric === "gpu") {
            return { usage: pct(gpuUsage.value), temp: deg(gpuTemp.value), peak: deg(gpuPeak), vram: fmt(gpuVram), vramtotal: fmt(gpuVramTotal), power: fmt(gpuPower) };
        }
        if (metric === "fan") {
            const v = fanValue();
            return { speed: rpm(v), rpm: (v === undefined || isNaN(v)) ? "—" : String(Math.round(v)), name: fanName() };
        }
        return {};
    }

    function metricFormat(metric) {
        return metric === "ram" ? Plasmoid.configuration.ramFormat
             : metric === "disk" ? Plasmoid.configuration.diskFormat
             : metric === "cpu" ? Plasmoid.configuration.cpuFormat
             : metric === "gpu" ? Plasmoid.configuration.gpuFormat
             : Plasmoid.configuration.fanFormat;
    }

    function expandTemplate(metric, tpl) {
        const vars = templateVars(metric);
        return tpl.replace(/\{(\w+)\}/g, (match, name) => vars[name] !== undefined ? vars[name] : match);
    }

    function partText(metric, part) {
        if (part === "custom") {
            return expandTemplate(metric, metricFormat(metric));
        }
        if (metric === "ram") {
            return part === "abs" ? fmt(ramUsed) : pct(ramSensor.value);
        }
        if (metric === "disk") {
            return part === "abs" ? diskUsed() : diskPercent();
        }
        if (metric === "cpu") {
            return part === "temp" ? deg(cpuTempMax.value) : pct(cpuUsage.value);
        }
        if (metric === "gpu") {
            return part === "temp" ? deg(gpuTemp.value) : pct(gpuUsage.value);
        }
        if (metric === "fan") {
            return rpm(fanValue());
        }
        return "—";
    }

    // Custom templates mix several values, so they color by the metric's
    // worst tier.
    function partTier(metric, part) {
        if (metric === "ram") {
            return ramTier;
        }
        if (metric === "disk") {
            return diskTier;
        }
        if (metric === "cpu") {
            return part === "usage" ? cpuUsageTier
                 : part === "temp" ? cpuTempTier
                 : Math.max(cpuUsageTier, cpuTempTier);
        }
        if (metric === "gpu") {
            return part === "usage" ? gpuUsageTier
                 : part === "temp" ? gpuTempTier
                 : Math.max(gpuUsageTier, gpuTempTier);
        }
        if (metric === "fan") {
            return fanTier;
        }
        return 0;
    }

    function partKind(part) {
        return part === "temp" ? "temp" : part === "abs" ? "abs" : part === "custom" ? "custom" : "pct";
    }

    // --- Appearance ------------------------------------------------------
    readonly property bool useIconLabels: Plasmoid.configuration.labelStyle === 1

    // Empty family / size 0 = follow the theme; labels scale with the
    // theme's small/default ratio
    readonly property string stripFontFamily: Plasmoid.configuration.fontFamily !== ""
        ? Plasmoid.configuration.fontFamily
        : Kirigami.Theme.defaultFont.family
    readonly property real stripPointSize: Plasmoid.configuration.fontSize > 0
        ? Plasmoid.configuration.fontSize
        : Kirigami.Theme.defaultFont.pointSize
    readonly property real labelPointSize: stripPointSize
        * Kirigami.Theme.smallFont.pointSize / Kirigami.Theme.defaultFont.pointSize

    // Each color independently falls back to the Plasma theme unless its
    // "custom" switch is on. Labels and separators default to the theme's
    // disabled-text (dimmed) color so values stand out.
    readonly property color valueColor: Plasmoid.configuration.customTextColor ? Plasmoid.configuration.textColor : Kirigami.Theme.textColor
    readonly property color labelColor: Plasmoid.configuration.customLabelColor ? Plasmoid.configuration.labelColor : Kirigami.Theme.disabledTextColor
    readonly property color sepColor: Plasmoid.configuration.customSeparatorColor ? Plasmoid.configuration.separatorColor : Kirigami.Theme.disabledTextColor
    readonly property color warnColor: Plasmoid.configuration.customWarningColor ? Plasmoid.configuration.warningColor : Kirigami.Theme.neutralTextColor
    readonly property color critColor: Plasmoid.configuration.customCriticalColor ? Plasmoid.configuration.criticalColor : Kirigami.Theme.negativeTextColor

    readonly property int ramTier: tier(ramSensor.value, Plasmoid.configuration.ramThreshold)
    // Disk usage is a capacity fact, not an emergency — never goes red
    readonly property int diskTier: Math.min(tier(root.diskUsage !== null ? root.diskUsage.percent : 0,
                                                 Plasmoid.configuration.diskThreshold), 1)
    readonly property int cpuUsageTier: tier(cpuUsage.value, Plasmoid.configuration.cpuUsageThreshold)
    readonly property int cpuTempTier: tier(cpuTempMax.value, Plasmoid.configuration.cpuTempThreshold)
    readonly property int gpuUsageTier: tier(gpuUsage.value, Plasmoid.configuration.gpuUsageThreshold)
    readonly property int gpuTempTier: tier(gpuTemp.value, Plasmoid.configuration.gpuTempThreshold)
    // A fan speed is not a "how bad" scale, so it has no "+10" step: amber at
    // the warning RPM and red at the critical RPM. A stopped or unread fan
    // stays uncoloured rather than red.
    readonly property int fanTier: {
        const v = fanValue();
        if (v === undefined || isNaN(v) || v <= 0) {
            return 0;
        }
        return v >= Plasmoid.configuration.fanCriticalThreshold ? 2
             : v >= Plasmoid.configuration.fanThreshold ? 1
             : 0;
    }

    // --- Alert notifications ---------------------------------------------
    //
    // The colors react to the value at every tick; a notification reports a
    // *crossing* instead — normal → amber → red — so a value that sits over its
    // threshold for an hour is announced once, a value that flaps across the
    // threshold at most once per alert per notifyCooldownMs, and an escalation
    // to red always, cooldown or not. The rules themselves are in
    // contents/ui/alerts.js, where they are tested without a Plasma session.
    //
    // Sending needs a notifyrc and a plasmoid cannot ship one (kpackagetool6
    // installs the plasmoid alone, and a notifyrc lives in the KDE data dirs),
    // so notifications go out as plasma_workspace's "notification" event: a
    // plain popup with no sound, and one the user can silence or give a sound
    // under System Settings > Notifications > System Notifications. Severity
    // rides on the urgency rather than on picking a louder event: amber is
    // Normal, red is Critical, and Plasma keeps a critical notification on
    // screen until it is dismissed.

    // Fixed on purpose: the threshold grid already carries eight rows, and a
    // repeat interval of its own for each alert would add seven more.
    readonly property int notifyCooldownMs: 300000

    readonly property var alertKeys: ["ram", "disk", "cpuUsage", "cpuTemp", "gpuUsage", "gpuTemp", "fan"]

    // One alert as the notification code sees it: its tier, the two thresholds
    // that tier was computed with, and the reading the message quotes — put
    // together with the strip's own formatters, so a notification reads exactly
    // like the row it belongs to. The unit is what the thresholds of that alert
    // are counted in, so a message can say "over the 85% threshold".
    function alertReading(key) {
        const c = Plasmoid.configuration;
        if (key === "ram") {
            return { tier: root.ramTier, warn: c.ramThreshold, crit: c.ramThreshold + 10,
                     text: i18n("RAM at %1", pct(ramSensor.value)), unit: "%" };
        }
        if (key === "disk") {
            // diskTier caps at amber, so the red level here is never quoted
            return { tier: root.diskTier, warn: c.diskThreshold, crit: c.diskThreshold + 10,
                     text: i18n("Disk at %1 used", diskPercent()), unit: "%" };
        }
        if (key === "cpuUsage") {
            return { tier: root.cpuUsageTier, warn: c.cpuUsageThreshold, crit: c.cpuUsageThreshold + 10,
                     text: i18n("CPU at %1", pct(cpuUsage.value)), unit: "%" };
        }
        if (key === "cpuTemp") {
            return { tier: root.cpuTempTier, warn: c.cpuTempThreshold, crit: c.cpuTempThreshold + 10,
                     text: i18n("CPU temperature %1", deg(cpuTempMax.value)), unit: "°C" };
        }
        if (key === "gpuUsage") {
            return { tier: root.gpuUsageTier, warn: c.gpuUsageThreshold, crit: c.gpuUsageThreshold + 10,
                     text: i18n("GPU at %1", pct(gpuUsage.value)), unit: "%" };
        }
        if (key === "gpuTemp") {
            return { tier: root.gpuTempTier, warn: c.gpuTempThreshold, crit: c.gpuTempThreshold + 10,
                     text: i18n("GPU temperature %1", deg(gpuTemp.value)), unit: "°C" };
        }
        return { tier: root.fanTier, warn: c.fanThreshold, crit: c.fanCriticalThreshold,
                 text: i18n("Fan speed %1", rpm(fanValue())), unit: "RPM" };
    }

    // "85%", "80 °C", "4000 RPM" — the number the user typed in the settings
    // page, with the unit that alert is counted in.
    function alertLevel(value, unit) {
        return unit === "%" ? value + "%" : value + " " + unit;
    }

    // Which alerts the user asked to be told about.
    function notifyEnabled(key) {
        const c = Plasmoid.configuration;
        return key === "ram" ? c.notifyRam
             : key === "disk" ? c.notifyDisk
             : key === "cpuUsage" ? c.notifyCpuUsage
             : key === "cpuTemp" ? c.notifyCpuTemp
             : key === "gpuUsage" ? c.notifyGpuUsage
             : key === "gpuTemp" ? c.notifyGpuTemp
             : c.notifyFan;
    }

    // One Notification object per alert, reused for the widget's lifetime: a
    // KNotification deletes itself after being closed in C++, but QML's
    // autoDelete is off, and one object per alert means two alerts crossing in
    // the same tick get one notification each instead of overwriting each
    // other.
    component AlertNotification : Notification {
        componentName: "plasma_workspace"
        eventId: "notification"
        flags: Notification.CloseOnTimeout
    }

    AlertNotification { id: alertRam }
    AlertNotification { id: alertDisk }
    AlertNotification { id: alertCpuUsage }
    AlertNotification { id: alertCpuTemp }
    AlertNotification { id: alertGpuUsage }
    AlertNotification { id: alertGpuTemp }
    AlertNotification { id: alertFan }

    function alertNotification(key) {
        return key === "ram" ? alertRam
             : key === "disk" ? alertDisk
             : key === "cpuUsage" ? alertCpuUsage
             : key === "cpuTemp" ? alertCpuTemp
             : key === "gpuUsage" ? alertGpuUsage
             : key === "gpuTemp" ? alertGpuTemp
             : alertFan;
    }

    // A notification icon is a theme icon *name* the server resolves, so an icon
    // that is a file path — which the icon dialog allows, and which the fan's
    // bundled SVG falls back to — would resolve to nothing. "cpuUsage" and
    // "cpuTemp" are two alerts on one metric and wear that metric's icon.
    function alertIcon(key) {
        const icon = String(root.metricIcon(key.replace(/(Usage|Temp)$/, "")));
        return icon.indexOf("/") === -1 ? icon : "utilities-system-monitor";
    }

    function announceAlert(key, reading) {
        const level = root.alertLevel(reading.tier === 2 ? reading.crit : reading.warn, reading.unit);
        const notification = root.alertNotification(key);
        notification.title = i18n("System Glance");
        notification.text = reading.tier === 2
            ? i18n("%1 — over the %2 critical level", reading.text, level)
            : i18n("%1 — over the %2 alert threshold", reading.text, level);
        notification.iconName = root.alertIcon(key);
        notification.urgency = reading.tier === 2 ? Notification.CriticalUrgency : Notification.NormalUrgency;
        notification.sendEvent();
    }

    // What each alert was last seen doing (see alerts.js).
    property var alertState: ({})

    function setAlertState(key, state) {
        const next = {};
        for (const k in root.alertState) {
            next[k] = root.alertState[k];
        }
        next[key] = state;
        root.alertState = next;
    }

    // The warm-up: the daemon hands a new subscriber the placeholder 0 and only
    // pushes the real value one updateRateLimit later, so without it a reload at
    // login would announce every value that happens to be over its threshold.
    // The five seconds are slack for a slow first push.
    property bool alertsArmed: false

    Timer {
        interval: root.rateMs + 5000
        running: true
        onTriggered: root.armAlerts()
    }

    function armAlerts() {
        const baseline = {};
        for (const key of root.alertKeys) {
            baseline[key] = Alerts.baseline(root.alertReading(key));
        }
        root.alertState = baseline;
        root.alertsArmed = true;
    }

    // One alert's check. Called from the tier change handlers below, so it runs
    // when a value moves across a threshold rather than on a timer of its own.
    function checkAlert(key) {
        const reading = root.alertReading(key);
        const result = Alerts.step(root.alertState[key], reading, {
            armed: root.alertsArmed,
            enabled: root.notifyEnabled(key),
            now: Date.now(),
            cooldownMs: root.notifyCooldownMs
        });
        root.setAlertState(key, result.state);
        if (result.send) {
            root.announceAlert(key, reading);
        }
    }

    // Every tier is a binding on the sensor values, so these fire exactly when a
    // value moves across a threshold — no polling of its own.
    onRamTierChanged: root.checkAlert("ram")
    onDiskTierChanged: root.checkAlert("disk")
    onCpuUsageTierChanged: root.checkAlert("cpuUsage")
    onCpuTempTierChanged: root.checkAlert("cpuTemp")
    onGpuUsageTierChanged: root.checkAlert("gpuUsage")
    onGpuTempTierChanged: root.checkAlert("gpuTemp")
    onFanTierChanged: root.checkAlert("fan")

    // Turning a switch on asks for the state of things now, so a value that is
    // already over its threshold is announced once at that moment; turning one
    // off is silent. The dialog writes one key at a time, which is why each
    // switch is watched individually.
    function alertSwitchChanged(key) {
        const reading = root.alertReading(key);
        const result = Alerts.switchedOn(reading, {
            armed: root.alertsArmed,
            enabled: root.notifyEnabled(key),
            now: Date.now()
        });
        root.setAlertState(key, result.state);
        if (result.send) {
            root.announceAlert(key, reading);
        }
    }

    Connections {
        target: Plasmoid.configuration

        function onNotifyRamChanged()      { root.alertSwitchChanged("ram"); }
        function onNotifyDiskChanged()     { root.alertSwitchChanged("disk"); }
        function onNotifyCpuUsageChanged() { root.alertSwitchChanged("cpuUsage"); }
        function onNotifyCpuTempChanged()  { root.alertSwitchChanged("cpuTemp"); }
        function onNotifyGpuUsageChanged() { root.alertSwitchChanged("gpuUsage"); }
        function onNotifyGpuTempChanged()  { root.alertSwitchChanged("gpuTemp"); }
        function onNotifyFanChanged()      { root.alertSwitchChanged("fan"); }
    }

    toolTipMainText: i18n("System Glance")
    toolTipSubText: [
        i18n("CPU %1 — hottest core %2, average %3",
             pct(cpuUsage.value), deg(cpuTempMax.value), deg(cpuTempAvg.value)),
        i18n("GPU %1 — %2 now, %3 peak (last 10 min)",
             pct(gpuUsage.value), deg(gpuTemp.value), deg(gpuPeak)),
        i18n("RAM %1 — %2 of %3",
             pct(ramSensor.value), fmt(ramUsed), fmt(ramTotal)),
        i18n("Disk %1 — %2 of %3 used",
             diskPercent(), diskUsed(), diskTotal()),
        root.fanConfigured ? i18n("Fan %1 — %2", fanName(), rpm(fanValue())) : "",
        "",
        i18n("Click for the full breakdown")
    ].join("\n")

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: source => disconnectSource(source)
    }

    // Kept for sizing icon labels to the strip's font height
    TextMetrics {
        id: pctMetrics
        font.family: root.stripFontFamily
        font.pointSize: root.stripPointSize
        text: "100%"
    }

    component GroupLabel : PC3.Label {
        visible: !root.useIconLabels
        color: root.labelColor
        font.family: root.stripFontFamily
        font.pointSize: root.labelPointSize
        Layout.alignment: Qt.AlignBaseline
    }

    // Icon alternative to GroupLabel — tracks the strip's font height so it
    // scales with the font size setting. Monochrome (symbolic) icons take
    // the label color; colorful ones keep their own palette.
    component MetricIcon : Kirigami.Icon {
        visible: root.useIconLabels
        color: root.labelColor
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Math.ceil(pctMetrics.height * 1.2)
        Layout.preferredHeight: Layout.preferredWidth
    }

    // Values use their natural width by default; a configured valueWidth
    // gives every slot the same fixed width (right-aligned, so the number
    // stays flush against what follows and the row never shifts as values
    // tick). Custom templates are free text and always fit their content.
    component Value : PC3.Label {
        property int tier: 0
        property string kind: "pct" // "pct" | "temp" | "abs" | "custom"
        horizontalAlignment: Text.AlignRight
        Layout.alignment: Qt.AlignBaseline
        Layout.preferredWidth: kind !== "custom" && Plasmoid.configuration.valueWidth > 0
            ? Plasmoid.configuration.valueWidth
            : -1
        font.family: root.stripFontFamily
        font.pointSize: root.stripPointSize
        font.features: ({ "tnum": 1 })
        color: root.tierColor(tier)
    }

    component Group : RowLayout {
        spacing: Plasmoid.configuration.valueGap
    }

    // `when` carries the between-visible-groups condition; the global
    // "show separators" switch is folded in here so instances stay simple.
    component Sep : PC3.Label {
        property bool when: true
        visible: Plasmoid.configuration.showSeparators && when
        text: "|"
        color: root.sepColor
        opacity: 0.5
        font.family: root.stripFontFamily
        font.pointSize: root.stripPointSize
        Layout.alignment: Qt.AlignBaseline
    }

    component SectionHeading : ColumnLayout {
        property alias text: sectionTitle.text

        spacing: Kirigami.Units.smallSpacing
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.largeSpacing

        Kirigami.Separator { Layout.fillWidth: true }

        PlasmaExtras.Heading {
            id: sectionTitle
            level: 4
        }
    }

    component DetailLabel : PC3.Label {
        font.features: ({ "tnum": 1 })
    }

    component DimLabel : PC3.Label {
        color: Kirigami.Theme.disabledTextColor
        font: Kirigami.Theme.smallFont
    }

    compactRepresentation: Item {
        Layout.preferredWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.minimumWidth: Layout.preferredWidth
        Layout.fillHeight: true

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Plasmoid.configuration.groupGap

            // One delegate per visible metric, in configured order; each
            // renders its parts in configured order. A separator leads every
            // group but the first, so they only appear between groups.
            Repeater {
                model: root.visibleMetrics

                delegate: RowLayout {
                    id: metricDelegate

                    required property var modelData
                    required property int index

                    spacing: Plasmoid.configuration.groupGap

                    Sep { when: metricDelegate.index > 0 }

                    Group {
                        MetricIcon { source: root.metricIcon(metricDelegate.modelData.key) }
                        GroupLabel { text: root.metricLabel(metricDelegate.modelData.key) }

                        Repeater {
                            model: metricDelegate.modelData.parts

                            delegate: Value {
                                required property string modelData
                                text: root.partText(metricDelegate.modelData.key, modelData)
                                tier: root.partTier(metricDelegate.modelData.key, modelData)
                                kind: root.partKind(modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    fullRepresentation: Item {
        id: popup

        Layout.preferredWidth: content.implicitWidth + Kirigami.Units.largeSpacing * 2
        Layout.preferredHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
        Layout.minimumWidth: Layout.preferredWidth
        Layout.minimumHeight: Layout.preferredHeight

        // The popup keeps the theme font, so it measures with its own metrics
        TextMetrics { id: popupPctMetrics; font: Kirigami.Theme.defaultFont; text: "100%" }
        TextMetrics { id: popupDegMetrics; font: Kirigami.Theme.defaultFont; text: "100°" }

        // Popup-only sensors — instantiated on first expand
        Sensors.Sensor { id: gpuName;      sensorId: "gpu/gpu0/name";              updateRateLimit: root.rateMs }
        Sensors.Sensor { id: gpuCoreFreq;  sensorId: "gpu/gpu0/coreFrequency";     updateRateLimit: root.rateMs }
        Sensors.Sensor { id: gpuMemFreq;   sensorId: "gpu/gpu0/memoryFrequency";   updateRateLimit: root.rateMs }
        Sensors.Sensor { id: swapUsed;     sensorId: "memory/swap/used";           updateRateLimit: root.rateMs }
        Sensors.Sensor { id: swapTotal;    sensorId: "memory/swap/total";          updateRateLimit: root.rateMs }

        ColumnLayout {
            id: content
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            RowLayout {
                PlasmaExtras.Heading {
                    level: 3
                    text: i18n("System Glance")
                    Layout.fillWidth: true
                }
                PC3.ToolButton {
                    icon.name: "utilities-system-monitor"
                    display: PC3.ToolButton.IconOnly
                    text: i18n("Open System Monitor")
                    PC3.ToolTip.text: text
                    PC3.ToolTip.visible: hovered
                    onClicked: {
                        exec.connectSource("plasma-systemmonitor");
                        root.expanded = false;
                    }
                }
            }

            SectionHeading { text: i18n("Memory") }
            DetailLabel {
                text: i18n("Used %1 — free %2 — of %3 (%4)",
                           root.fmt(ramUsed), root.fmt(ramFree), root.fmt(ramTotal), root.pct(ramSensor.value))
            }
            DetailLabel {
                text: i18n("Swap: %1 of %2 used", root.fmt(swapUsed), root.fmt(swapTotal))
            }

            SectionHeading { text: i18n("Disks") }

            GridLayout {
                columns: 3
                columnSpacing: Kirigami.Units.largeSpacing
                rowSpacing: Kirigami.Units.smallSpacing / 2

                DimLabel { text: i18n("All disks") }
                DetailLabel {
                    text: root.diskPercent()
                    color: root.tierColor(root.diskTier)
                }
                DetailLabel { text: i18n("%1 used, %2 free of %3", root.diskUsed(), root.diskFree(), root.diskTotal()) }

                Repeater {
                    // One row per counted filesystem, from the same read as the
                    // "All disks" line above. A filesystem nested inside a
                    // larger one on its own drive (a /boot partition, say) is
                    // not counted and not listed.
                    model: root.diskFilesystems

                    delegate: DimLabel {
                        id: partNameLabel

                        required property var modelData
                        required property int index

                        text: modelData.name
                        Layout.row: 1 + index
                        Layout.column: 0
                        Layout.maximumWidth: Kirigami.Units.gridUnit * 14
                        elide: Text.ElideMiddle
                    }
                }

                Repeater {
                    model: root.diskFilesystems

                    delegate: DetailLabel {
                        id: partPctLabel

                        required property var modelData
                        required property int index

                        text: root.pct(modelData.percent)
                        Layout.row: 1 + index
                        Layout.column: 1
                    }
                }

                Repeater {
                    model: root.diskFilesystems

                    delegate: DetailLabel {
                        id: partDetailLabel

                        required property var modelData
                        required property int index

                        text: i18n("%1 used, %2 free of %3",
                                   root.fmtBytes(modelData.used), root.fmtBytes(modelData.free), root.fmtBytes(modelData.total))
                        Layout.row: 1 + index
                        Layout.column: 2
                    }
                }

                // Only shown when the mount table could not be read at all,
                // in which case the values above stay at their last good state.
                DetailLabel {
                    visible: root.diskError !== ""
                    text: i18n("Disk values unavailable: %1", root.diskError)
                    color: root.warnColor
                    Layout.row: 1 + root.diskFilesystems.length
                    Layout.column: 0
                    Layout.columnSpan: 3
                }
            }

            SectionHeading { text: i18n("CPU") }
            DetailLabel {
                text: i18n("%1 — hottest core %2, average %3",
                           root.pct(cpuUsage.value), root.deg(cpuTempMax.value), root.deg(cpuTempAvg.value))
            }

            GridLayout {
                columns: 2
                columnSpacing: Kirigami.Units.largeSpacing * 2
                rowSpacing: 0

                Repeater {
                    model: cpuCount.value !== undefined ? cpuCount.value : 0

                    delegate: RowLayout {
                        id: coreRow

                        required property int index

                        spacing: Kirigami.Units.smallSpacing

                        Sensors.Sensor { id: coreUsage; sensorId: "cpu/cpu" + coreRow.index + "/usage";       updateRateLimit: root.rateMs }
                        Sensors.Sensor { id: coreTemp;  sensorId: "cpu/cpu" + coreRow.index + "/temperature"; updateRateLimit: root.rateMs }
                        Sensors.Sensor { id: coreFreq;  sensorId: "cpu/cpu" + coreRow.index + "/frequency";   updateRateLimit: root.rateMs }

                        DimLabel {
                            text: "C" + (coreRow.index < 10 ? "0" : "") + coreRow.index
                        }
                        DetailLabel {
                            text: root.pct(coreUsage.value)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Math.ceil(popupPctMetrics.advanceWidth)
                        }
                        DetailLabel {
                            text: root.deg(coreTemp.value)
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Math.ceil(popupDegMetrics.advanceWidth)
                        }
                        DetailLabel {
                            text: root.fmt(coreFreq)
                            color: Kirigami.Theme.disabledTextColor
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 4
                        }
                    }
                }
            }

            SectionHeading { text: root.fmt(gpuName) !== "—" ? i18n("GPU — %1", root.fmt(gpuName)) : i18n("GPU") }
            DetailLabel {
                text: i18n("%1 — %2 now, %3 peak (last 10 min)",
                           root.pct(gpuUsage.value), root.deg(gpuTemp.value), root.deg(root.gpuPeak))
            }
            DetailLabel {
                text: i18n("VRAM %1 of %2 — drawing %3",
                           root.fmt(gpuVram), root.fmt(gpuVramTotal), root.fmt(gpuPower))
            }
            DetailLabel {
                text: i18n("Clocks: core %1, memory %2",
                           root.fmt(gpuCoreFreq), root.fmt(gpuMemFreq))
            }

            SectionHeading { text: i18n("Fan") }
            DetailLabel {
                text: root.fanConfigured
                    ? i18n("%1 — %2", root.fanName(), root.rpm(root.fanValue()))
                    : i18n("No fan sensor chosen — pick one in the widget settings")
                color: root.tierColor(root.fanTier)
            }

            Item { Layout.fillHeight: true }
        }
    }
}
