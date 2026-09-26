import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page

    // Align content with the dialog's page title, which is inset ~1 gridUnit
    leftPadding: Kirigami.Units.gridUnit
    rightPadding: Kirigami.Units.gridUnit
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.largeSpacing

    // Absorb the cfg_<key>Default initial properties the config dialog sets
    property int cfg_updateIntervalDefault: 0

    // The dialog pushes every config key into every page — absorb the
    // Appearance page's keys so they don't log warnings here.
    property string cfg_metricOrder; property string cfg_metricOrderDefault: ""
    property bool cfg_ramShown; property bool cfg_ramShownDefault: false
    property bool cfg_diskShown; property bool cfg_diskShownDefault: false
    property bool cfg_cpuShown; property bool cfg_cpuShownDefault: false
    property bool cfg_gpuShown; property bool cfg_gpuShownDefault: false
    property bool cfg_fanShown; property bool cfg_fanShownDefault: false
    property string cfg_fanSensorId; property string cfg_fanSensorIdDefault: ""
    property string cfg_ramParts; property string cfg_ramPartsDefault: ""
    property string cfg_diskParts; property string cfg_diskPartsDefault: ""
    property string cfg_cpuParts; property string cfg_cpuPartsDefault: ""
    property string cfg_gpuParts; property string cfg_gpuPartsDefault: ""
    property string cfg_fanParts; property string cfg_fanPartsDefault: ""
    property string cfg_ramFormat; property string cfg_ramFormatDefault: ""
    property string cfg_diskFormat; property string cfg_diskFormatDefault: ""
    property string cfg_cpuFormat; property string cfg_cpuFormatDefault: ""
    property string cfg_gpuFormat; property string cfg_gpuFormatDefault: ""
    property string cfg_fanFormat; property string cfg_fanFormatDefault: ""
    property int cfg_labelStyle; property int cfg_labelStyleDefault: 0
    property int cfg_fontSize; property int cfg_fontSizeDefault: 0
    property string cfg_fontFamily; property string cfg_fontFamilyDefault: ""
    property int cfg_valueGap; property int cfg_valueGapDefault: 0
    property int cfg_groupGap; property int cfg_groupGapDefault: 0
    property int cfg_valueWidth; property int cfg_valueWidthDefault: 0
    property bool cfg_showSeparators; property bool cfg_showSeparatorsDefault: false
    property string cfg_separatorColor; property string cfg_separatorColorDefault: ""
    property bool cfg_customTextColor; property bool cfg_customTextColorDefault: false
    property bool cfg_customLabelColor; property bool cfg_customLabelColorDefault: false
    property bool cfg_customSeparatorColor; property bool cfg_customSeparatorColorDefault: false
    property bool cfg_customWarningColor; property bool cfg_customWarningColorDefault: false
    property bool cfg_customCriticalColor; property bool cfg_customCriticalColorDefault: false
    property string cfg_ramLabel; property string cfg_ramLabelDefault: ""
    property string cfg_diskLabel; property string cfg_diskLabelDefault: ""
    property string cfg_cpuLabel; property string cfg_cpuLabelDefault: ""
    property string cfg_gpuLabel; property string cfg_gpuLabelDefault: ""
    property string cfg_fanLabel; property string cfg_fanLabelDefault: ""
    property string cfg_ramIcon; property string cfg_ramIconDefault: ""
    property string cfg_diskIcon; property string cfg_diskIconDefault: ""
    property string cfg_cpuIcon; property string cfg_cpuIconDefault: ""
    property string cfg_gpuIcon; property string cfg_gpuIconDefault: ""
    property string cfg_fanIcon; property string cfg_fanIconDefault: ""
    property string cfg_textColor; property string cfg_textColorDefault: ""
    property string cfg_labelColor; property string cfg_labelColorDefault: ""
    property string cfg_warningColor; property string cfg_warningColorDefault: ""
    property string cfg_criticalColor; property string cfg_criticalColorDefault: ""
    property int cfg_ramThresholdDefault: 0
    property int cfg_diskThresholdDefault: 0
    property int cfg_cpuUsageThresholdDefault: 0
    property int cfg_cpuTempThresholdDefault: 0
    property int cfg_gpuUsageThresholdDefault: 0
    property int cfg_gpuTempThresholdDefault: 0
    property int cfg_fanThresholdDefault: 0
    property int cfg_fanCriticalThresholdDefault: 0
    property bool cfg_notifyRamDefault: false
    property bool cfg_notifyDiskDefault: false
    property bool cfg_notifyCpuUsageDefault: false
    property bool cfg_notifyCpuTempDefault: false
    property bool cfg_notifyGpuUsageDefault: false
    property bool cfg_notifyGpuTempDefault: false
    property bool cfg_notifyFanDefault: false

    property alias cfg_updateInterval: updateIntervalSpin.value
    property alias cfg_ramThreshold: ramSpin.value
    property alias cfg_diskThreshold: diskSpin.value
    property alias cfg_cpuUsageThreshold: cpuUsageSpin.value
    property alias cfg_cpuTempThreshold: cpuTempSpin.value
    property alias cfg_gpuUsageThreshold: gpuUsageSpin.value
    property alias cfg_gpuTempThreshold: gpuTempSpin.value
    property alias cfg_fanThreshold: fanSpin.value
    property alias cfg_fanCriticalThreshold: fanCriticalSpin.value
    property alias cfg_notifyRam: notifyRamCheck.checked
    property alias cfg_notifyDisk: notifyDiskCheck.checked
    property alias cfg_notifyCpuUsage: notifyCpuUsageCheck.checked
    property alias cfg_notifyCpuTemp: notifyCpuTempCheck.checked
    property alias cfg_notifyGpuUsage: notifyGpuUsageCheck.checked
    property alias cfg_notifyGpuTemp: notifyGpuTempCheck.checked
    property alias cfg_notifyFan: notifyFanCheck.checked

    component FieldLabel : QQC2.Label {
        Layout.alignment: Qt.AlignRight
    }

    // The third column of the threshold grid: a bare box under a "Notify"
    // heading, with its accessible name carrying what the heading cannot.
    component NotifyCheck : QQC2.CheckBox {
        property string alertName

        Layout.alignment: Qt.AlignLeft
        Accessible.name: alertName !== ""
            ? i18n("Notify when %1 crosses its alert threshold", alertName)
            : i18n("Notify")
    }

    // Reset every General option to its main.xml default
    function restoreDefaults() {
        cfg_updateInterval = cfg_updateIntervalDefault;
        cfg_ramThreshold = cfg_ramThresholdDefault;
        cfg_diskThreshold = cfg_diskThresholdDefault;
        cfg_cpuUsageThreshold = cfg_cpuUsageThresholdDefault;
        cfg_cpuTempThreshold = cfg_cpuTempThresholdDefault;
        cfg_gpuUsageThreshold = cfg_gpuUsageThresholdDefault;
        cfg_gpuTempThreshold = cfg_gpuTempThresholdDefault;
        cfg_fanThreshold = cfg_fanThresholdDefault;
        cfg_fanCriticalThreshold = cfg_fanCriticalThresholdDefault;
        cfg_notifyRam = cfg_notifyRamDefault;
        cfg_notifyDisk = cfg_notifyDiskDefault;
        cfg_notifyCpuUsage = cfg_notifyCpuUsageDefault;
        cfg_notifyCpuTemp = cfg_notifyCpuTempDefault;
        cfg_notifyGpuUsage = cfg_notifyGpuUsageDefault;
        cfg_notifyGpuTemp = cfg_notifyGpuTempDefault;
        cfg_notifyFan = cfg_notifyFanDefault;
    }

    // Rendered right-aligned on the page-title row by the dialog's header
    actions: [
        Kirigami.Action {
            icon.name: "document-revert"
            text: i18n("Restore Defaults")
            onTriggered: page.restoreDefaults()
        }
    ]

    // Plain two-column grid instead of Kirigami.FormLayout: the form hugs
    // the left edge rather than centering in the page (which left a large
    // dead zone on the left).
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        GridLayout {
            columns: 2
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignLeft

            FieldLabel { text: i18n("Update interval (seconds):") }
            QQC2.SpinBox {
                id: updateIntervalSpin
                from: 1
                to: 60
            }
        }

        QQC2.Label {
            text: i18n("Alert thresholds")
            font.bold: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Values turn amber at the threshold and red at threshold + 10. Disk only ever turns amber; the fan speed has its own warning and critical values.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Notify sends a desktop notification when a value crosses into a worse state — amber once, red once — rather than on every update. The same state is not announced twice inside five minutes; an escalation to red always is. A switch turned on while a value is already over its threshold announces it at that moment, and only that once.")
            font: Kirigami.Theme.smallFont
            wrapMode: Text.WordWrap
        }

        GridLayout {
            columns: 3
            columnSpacing: Kirigami.Units.largeSpacing
            rowSpacing: Kirigami.Units.smallSpacing
            Layout.alignment: Qt.AlignLeft

            // Heading for the third column; the first two are labelled per row.
            Item { }
            Item { }
            QQC2.Label {
                text: i18n("Notify")
                font.bold: true
            }

            FieldLabel { text: i18n("RAM alert threshold (%):") }
            QQC2.SpinBox {
                id: ramSpin
                from: 1
                to: 100
            }
            NotifyCheck { id: notifyRamCheck; alertName: i18n("RAM") }

            FieldLabel { text: i18n("Disk alert threshold (%):") }
            QQC2.SpinBox {
                id: diskSpin
                from: 1
                to: 100
            }
            NotifyCheck { id: notifyDiskCheck; alertName: i18n("disk usage") }

            FieldLabel { text: i18n("CPU usage alert threshold (%):") }
            QQC2.SpinBox {
                id: cpuUsageSpin
                from: 1
                to: 100
            }
            NotifyCheck { id: notifyCpuUsageCheck; alertName: i18n("CPU usage") }

            FieldLabel { text: i18n("CPU temperature alert (°C):") }
            QQC2.SpinBox {
                id: cpuTempSpin
                from: 30
                to: 110
            }
            NotifyCheck { id: notifyCpuTempCheck; alertName: i18n("CPU temperature") }

            FieldLabel { text: i18n("GPU usage alert threshold (%):") }
            QQC2.SpinBox {
                id: gpuUsageSpin
                from: 1
                to: 100
            }
            NotifyCheck { id: notifyGpuUsageCheck; alertName: i18n("GPU usage") }

            FieldLabel { text: i18n("GPU temperature alert (°C):") }
            QQC2.SpinBox {
                id: gpuTempSpin
                from: 30
                to: 110
            }
            NotifyCheck { id: notifyGpuTempCheck; alertName: i18n("GPU temperature") }

            FieldLabel { text: i18n("Fan speed alert (RPM):") }
            QQC2.SpinBox {
                id: fanSpin
                from: 100
                to: 20000
                stepSize: 100
            }
            NotifyCheck { id: notifyFanCheck; alertName: i18n("fan speed") }

            FieldLabel { text: i18n("Fan speed critical (RPM):") }
            QQC2.SpinBox {
                id: fanCriticalSpin
                from: 100
                to: 20000
                stepSize: 100
            }
            Item { }
        }
    }
}
