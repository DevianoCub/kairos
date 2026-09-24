import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

// ─────────────────────────────────────────────
// KAIROS SYSTEM SERVICE
//
// Owns all machine telemetry for the shell. The UI
// never spawns processes or parses /proc itself — it
// only binds to state exposed here.
//
// Exposed state:
//   currentTime / currentDate   clock (native, no process)
//   memoryPercent               RAM used %
//   loadAverage                 1-minute load
//   uptimeText                  uptime, compact
//   cpuPercent / cpuPercentValue     CPU busy % (delta of /proc/stat)
//   netRxText / netTxText / networkInterface  LAN rates (delta of /proc/net/dev)
//   temperatureText             max on-die temp (thermal zones)
//   cpuHistory / netRxHistory / netTxHistory  bounded series for Graphs
//   compositorName              detected compositor (NIRI, MANGO, ...)
//   status / statusLabel        synthetic KAIROS state
// ─────────────────────────────────────────────

// Non-visual service host. Zero-size Item so it can own
// Timer / Process / SystemClock children; never rendered.
Item {
    id: system
    width: 0
    height: 0
    visible: false

    // ─────────────────────────────────────────────
    // CLOCK STATE
    // Native Quickshell clock; no subprocess needed.
    // ─────────────────────────────────────────────

    SystemClock {
        id: sysClock
        enabled: true
        precision: SystemClock.Seconds
    }

    property string currentTime: {
        const format = Settings.clockFormat
        return format !== "" ? Qt.formatDateTime(sysClock.date, format) : "--:--:--"
    }
    property string currentDate: {
        const format = Settings.dateFormat
        return format !== "" ? Qt.formatDateTime(sysClock.date, format) : "--"
    }

    // ─────────────────────────────────────────────
    // LIVE STATE
    // ─────────────────────────────────────────────

    property string memoryPercent: "N/A"
    property string loadAverage: "--"
    property string uptimeText: "--"

    property double memoryPercentValue: 0
    property double loadOne: 0

    // v0.2 telemetry
    property string cpuPercent: "--"
    property double cpuPercentValue: 0
    property string netRxText: "--"
    property string netTxText: "--"
    property double netRxValue: 0
    property double netTxValue: 0
    property string networkInterface: ""
    property string temperatureText: "N/A"
    property double temperatureValue: 0

    // Bounded histories for Graph primitives.
    property variant cpuHistory: []
    property variant netRxHistory: []
    property variant netTxHistory: []

    // Raw snapshot for delta math (never displayed).
    property double prevCpuTotal: -1
    property double prevCpuIdle: -1
    property double prevNetRx: -1
    property double prevNetTx: -1

    property string status: "ok"
    property string statusLabel: "ONLINE"

    readonly property string compositorName: detectCompositor()

    // ─────────────────────────────────────────────
    // SYSTEM SAMPLE (1 Hz)
    // One short-lived process per tick reads all
    // /proc sources in a single pipeline, then parsed
    // in collect().
    // ─────────────────────────────────────────────

    Process {
        id: sysProcess

        command: [
            "sh",
            "-c",
            "awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf \"MEM %d %d\\n\", t, a}' /proc/meminfo;"
            + " awk 'NR==1{for(i=2;i<=NF;i++){t+=$i}; id=$5} END{printf \"CPU %d %d\\n\", t, id}' /proc/stat;"
            + " awk 'NR==1{printf \"LOAD %s\\n\", $1}' /proc/loadavg;"
            + " awk '{printf \"UP %d\\n\", int($1)}' /proc/uptime;"
            + " awk 'NR>2{sub(\":\",\"\",$1); if($1!=\"lo\" && $2+0>max){max=$2+0; iface=$1; rx=$2; tx=$10}}"
            + "     END{if(iface!=\"\")printf \"NET %s %d %d\\n\", iface, rx, tx}' /proc/net/dev;"
            + " awk '$1+0>max && $1+0>0{max=$1+0} END{if(max>0)printf \"TEMP %d\\n\", max}'"
            + "     /sys/class/thermal/thermal_zone*/temp 2>/dev/null"
        ]

        stdout: StdioCollector {
            id: sysCollector

            onStreamFinished: system.collect(sysCollector.text)
        }
    }

    Timer {
        interval: Settings.refreshMs
        running: true
        repeat: true

        onTriggered: system.poll()
    }

    // ─────────────────────────────────────────────
    // POLL / COLLECT
    // ─────────────────────────────────────────────

    function poll() {
        if (!sysProcess.running) {
            sysProcess.running = true
        }
    }

    function collect(text) {
        const lines = text.trim().split("\n")

        for (const line of lines) {
            const parts = line.split(" ")

            if (parts.length < 2) {
                continue
            }

            switch (parts[0]) {
            case "MEM": {
                const total = Number(parts[1])
                const available = Number(parts[2])

                if (total > 0) {
                    const used = Math.max(0, Math.min(100, (1 - available / total) * 100))
                    memoryPercent = Math.round(used) + "%"
                    memoryPercentValue = used
                } else {
                    memoryPercent = "N/A"
                }
                break
            }
            case "LOAD": {
                const value = Number(parts[1])
                loadOne = value
                loadAverage = value.toFixed(2)
                break
            }
            case "UP": {
                uptimeText = formatUptime(Number(parts[1]))
                break
            }
            case "CPU": {
                const total = Number(parts[1])
                const idle = Number(parts[2])

                if (system.prevCpuTotal >= 0 && system.prevCpuIdle >= 0) {
                    const dTotal = total - system.prevCpuTotal
                    const dIdle = idle - system.prevCpuIdle

                    if (dTotal > 0) {
                        const pct = Math.max(0, Math.min(100, (1 - dIdle / dTotal) * 100))
                        system.cpuPercentValue = pct
                        system.cpuPercent = (Math.round(pct * 10) / 10).toFixed(1) + "%"
                        system.cpuHistory = system.pushHistory(system.cpuHistory, pct)
                    }
                }

                system.prevCpuTotal = total
                system.prevCpuIdle = idle
                break
            }
            case "NET": {
                const iface = parts[1]
                const rx = Number(parts[2])
                const tx = Number(parts[3])

                if (system.prevNetRx >= 0 && system.prevNetTx >= 0) {
                    const dRx = Math.max(0, rx - system.prevNetRx)
                    const dTx = Math.max(0, tx - system.prevNetTx)

                    system.netRxValue = dRx / 1024
                    system.netTxValue = dTx / 1024
                    system.netRxText = system.formatRate(dRx / 1024)
                    system.netTxText = system.formatRate(dTx / 1024)
                    system.networkInterface = iface
                    system.netRxHistory = system.pushHistory(system.netRxHistory, dRx / 1024)
                    system.netTxHistory = system.pushHistory(system.netTxHistory, dTx / 1024)
                }

                system.prevNetRx = rx
                system.prevNetTx = tx
                break
            }
            case "TEMP": {
                const temp = Number(parts[1]) / 1000

                if (temp > 0) {
                    system.temperatureValue = temp
                    system.temperatureText = Math.round(temp) + "°C"
                }
                break
            }
            }
        }

        updateStatus()
    }

    function formatUptime(totalSeconds) {
        if (isNaN(totalSeconds) || totalSeconds < 0) {
            return "--"
        }

        const days = Math.floor(totalSeconds / 86400)
        const hours = Math.floor((totalSeconds % 86400) / 3600)
        const minutes = Math.floor((totalSeconds % 3600) / 60)
        const seconds = Math.floor(totalSeconds % 60)

        const pad = (n) => String(n).padStart(2, "0")
        const tail = `${pad(hours)}:${pad(minutes)}:${pad(seconds)}`

        return days > 0 ? `${days}d ${tail}` : tail
    }

    function pushHistory(history, value) {
        const pushed = history.concat([value])
        const maxLen = Settings.graphSamples

        return pushed.length > maxLen ? pushed.slice(pushed.length - maxLen) : pushed
    }

    function formatRate(kilobytesPerSecond) {
        if (isNaN(kilobytesPerSecond) || kilobytesPerSecond < 0) {
            return "--"
        }

        if (kilobytesPerSecond >= 1024) {
            return (kilobytesPerSecond / 1024).toFixed(1) + "M"
        }

        return Math.round(kilobytesPerSecond) + "K"
    }

    // Synthetic state derived from real readings. The HUD reacts to this;
    // thresholds own the tone, values own the fact.
    function updateStatus() {
        const temp = system.temperatureValue
        const mem = system.memoryPercentValue
        const cpu = system.cpuPercentValue

        if (temp >= 80 || mem >= 90 || cpu >= 95) {
            status = "critical"
            statusLabel = "CRITICAL"
        } else if (cpu >= 90 || temp >= 70 || loadOne >= 4) {
            status = "warning"
            statusLabel = "CAUTION"
        } else {
            status = "ok"
            statusLabel = "ONLINE"
        }
    }

    // ─────────────────────────────────────────────
    // COMPOSITOR DETECTION
    // Compositor-agnostic: reports whatever Wayland
    // compositor is running (NIRI, MANGO, ...) so the
    // HUD needs no per-WM code paths in v0.1.
    // ─────────────────────────────────────────────

    function detectCompositor() {
        const candidates = ["XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "WAYLAND_DESKTOP"]

        for (const key of candidates) {
            const raw = Quickshell.env(key)

            if (raw !== "") {
                return raw.split(":")[0].toUpperCase()
            }
        }

        return "WAYLAND"
    }

    Component.onCompleted: poll()
}