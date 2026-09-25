import QtQuick
import Quickshell

// ─────────────────────────────────────────────
// KAIROS APP LAUNCHER SERVICE (v0.5)
//
// Owns application discovery, the application
// model, searching and launching. The launcher UI
// binds ONLY to `results` and never touches
// desktop files, subprocesses or fuzzy logic.
//
// DISCOVERY
//   Sources the built-in Quickshell desktop entry
//   index (`Quickshell.DesktopEntries`):
//     - reads the standard XDG desktop entry
//       locations (XDG_DATA_DIRS/XDG_DATA_HOME,
//       /usr/share/applications, ~/.local/share/
//       applications, ...)
//     - exposes Application entries that are not
//       Hidden and not NoDisplay — i.e. only valid
//       launchable apps
//     - live-monitors the directories and emits
//       `applicationsChanged` when files appear or
//       disappear (QFileSystemWatcher + debounce).
//   KAIROS never hardcodes an app and never
//   rescans on keystrokes: the index refresh is
//   coalesced and driven ONLY by those change
//   events.
//
// MODEL
//   A snapshot list is rebuilt once per index
//   change: id, name, generic name, comment, icon,
//   categories, keywords and the underlying
//   DesktopEntry. Ordering is deterministic (name,
//   then id) so the UI is stable across sessions.
//
// SEARCH
//   Pure in-memory, per keystroke: prefix/substring
//   and subsequence scoring over lowercased name,
//   generic name, id, keywords, categories and
//   comment. Deterministic ranking + tie-breaks; no
//   process or file access anywhere in the path.
//
// LAUNCH
//   `DesktopEntry.execute()` runs the parsed Exec
//   argv detached (no shell, no injection). Quickshell
//   has already tokenized the string and dropped
//   argument field codes (%U %u %F %f %i %c %k),
//   collapsing %% to %. Launching without files/URLs
//   is therefore always correct. Terminal=true
//   entries run raw (no TTY) — v0.5 policy.
//
// No compositor knowledge. Works on any backend.
// ─────────────────────────────────────────────

// Non-visual service host.
Item {
    id: launcher
    width: 0
    height: 0
    visible: false

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────

    // Live search query (drives `results`).
    property string query: ""

    // Model + last search, as plain JS snapshots:
    //   { entry, id, name, genericName, comment,
    //     icon, categories, keywords, tokens, score }
    property variant _entries: []
    property variant results: []

    // Instrumentation for the docs / tests.
    readonly property int appCount: launcher._entries.length

    // Launched the given DesktopEntry.
    signal launched(var entry)
    // Convenience string form.
    signal launchedName(string name)
    // Model rebuilt (index change), not per keystroke.
    signal modelChanged()

    // ─────────────────────────────────────────────
    // DISCOVERY → MODEL
    // ─────────────────────────────────────────────

    function _tokenize(name, genericName, id, keywords, categories, comment) {
        return (name + " " + genericName + " " + id.toLowerCase().replace(".desktop", "") + " "
            + keywords.join(" ") + " " + categories.join(" ") + " " + comment).toLowerCase()
    }

    // Copy a QML-exposed string list into a plain JS
    // array (QML arrays can surface as QVector-backed,
    // so plain copies keep every path uniform).
    function _listOf(src) {
        const n = src !== null && src !== undefined ? src.length : 0
        const out = []
        for (let i = 0; i < n; i++) out.push(String(src[i]))
        return out
    }

    // Rebuild the snapshot model from the Quickshell
    // desktop-entry index. Deterministic ordering.
    function refresh() {
        const apps = DesktopEntries.applications
        const list = apps !== null && apps !== undefined && apps.values ? apps.values : []
        const out = []

        for (const de of list) {
            if (de === null || de === undefined) continue

            const name = (de.name || "").trim()
            if (name === "") continue // invalid/nameless entries are not launchable

            const id = de.id || ""
            const genericName = (de.genericName || "").trim()
            const keywords = launcher._listOf(de.keywords)
            const categories = launcher._listOf(de.categories)
            out.push({
                entry: de,
                id: id,
                name: name,
                genericName: genericName,
                comment: (de.comment || "").trim(),
                icon: de.icon || "",
                categories: categories,
                keywords: keywords,
                tokens: launcher._tokenize(name, genericName, id,
                    keywords, categories, de.comment || ""),
                score: 0
            })
        }

        out.sort(function (a, b) {
            const c = a.name.localeCompare(b.name)
            if (c !== 0) return c
            return a.id.localeCompare(b.id)
        })

        launcher._entries = out
        launcher.recompute()
        launcher.modelChanged()
        console.info(`[Launcher] desktop index: ${out.length} apps`)
    }

    // Coalesced rebuild: the Quickshell monitor may
    // fire rapid successions; never run two scans at
    // once and never scan while another is pending.
    property bool _refreshQueued: false
    function queueRefresh() {
        if (launcher._refreshQueued) return
        launcher._refreshQueued = true
        Qt.callLater(function () {
            launcher._refreshQueued = false
            launcher.refresh()
        })
    }

    // ─────────────────────────────────────────────
    // SEARCH
    // ─────────────────────────────────────────────

    function _matchSub(hay, q) {
        const i = hay.indexOf(q)
        if (i >= 0) return i

        let hi = 0
        let qIdx = 0
        while (qIdx < q.length && hi < hay.length) {
            if (hay.charCodeAt(hi) === q.charCodeAt(qIdx)) qIdx++
            hi++
        }
        return qIdx === q.length ? hi - q.length : -1
    }

    function _score(e, q) {
        const name = e.name.toLowerCase()
        const gen = e.genericName.toLowerCase()
        const idTok = e.id.toLowerCase().replace(".desktop", "")
        let s = 0

        // Name hits are the strongest signal.
        const inName = launcher._matchSub(name, q)
        if (inName >= 0) {
            s += 1000 - inName           // earlier prefix beats later substring
            if (inName === 0) s += 5000  // prefix wins outright
        } else {
            const inGen = launcher._matchSub(gen, q)
            if (inGen >= 0) {
                s += 400 - inGen
            } else {
                const inId = launcher._matchSub(idTok, q)
                if (inId >= 0) s += 300 - inId
            }
        }

        // Subsequence fuzz on name (weaker than any direct hit).
        if (inName < 0) {
            const subName = launcher._subseqScore(name, q)
            if (subName > 0) s += subName
        }

        // Soft signals: keywords / categories / comment / generic name.
        if (launcher._matchSub(e.tokens, q) >= 0) {
            if (e.keywords.indexOf(q) >= 0) s += 120
            else if (e.categories.indexOf(q) >= 0) s += 80
            else if (e.comment.toLowerCase().indexOf(q) >= 0) s += 60
            else s += 30
        }

        return s
    }

    // Subsequence fuzzy: how many consecutive leading chars
    // match in order; returns points only if the full query
    // is a subsequence.
    function _subseqScore(hay, q) {
        let hi = 0
        let qIdx = 0
        let gaps = 0
        while (qIdx < q.length && hi < hay.length) {
            if (hay.charCodeAt(hi) === q.charCodeAt(qIdx)) {
                qIdx++
            } else {
                gaps++
            }
            hi++
        }
        if (qIdx !== q.length) return 0
        return 150 + Math.max(0, 40 - gaps)
    }

    // Recompute results for the current query. Pure memory.
    function recompute() {
        const q = launcher.query.trim().toLowerCase()

        if (q === "") {
            // Empty query: full catalog, deterministic, capped for sanity.
            const all = []
            for (const e of launcher._entries) {
                all.push({
                    entry: e.entry, id: e.id, name: e.name,
                    genericName: e.genericName, comment: e.comment,
                    icon: e.icon, categories: e.categories, keywords: e.keywords,
                    tokens: e.tokens, score: 0
                })
            }
            launcher.results = all
            return
        }

        const matched = []
        for (const e of launcher._entries) {
            const score = launcher._score(e, q)
            if (score > 0) {
                matched.push({
                    entry: e.entry, id: e.id, name: e.name,
                    genericName: e.genericName, comment: e.comment,
                    icon: e.icon, categories: e.categories, keywords: e.keywords,
                    tokens: e.tokens, score: score
                })
            }
        }

        matched.sort(function (a, b) {
            if (a.score !== b.score) return b.score - a.score
            const c = a.name.localeCompare(b.name)
            if (c !== 0) return c
            return a.id.localeCompare(b.id)
        })

        launcher.results = matched
    }

    // ─────────────────────────────────────────────
    // LAUNCH
    // ─────────────────────────────────────────────

    // Launch a result (or raw DesktopEntry) detached.
    // `execute()` uses the parsed argv + working
    // directory; no shell, no injection, no field-code
    // leakage (codes were stripped at parse time).
    function launch(what) {
        const de = what && what.entry ? what.entry : what
        if (de === null || de === undefined) return false

        try {
            de.execute()
        } catch (err) {
            console.warn(`[Launcher] refused to launch ${de.id}: ${err}`)
            return false
        }

        const name = (what && what.name ? what.name : de.name) || de.id
        launcher.launched(de)
        launcher.launchedName(name)
        console.info(`[Launcher] launched ${name} (${de.id})`)
        return true
    }

    // ─────────────────────────────────────────────
    // WIRING
    // ─────────────────────────────────────────────

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            launcher.queueRefresh()
        }
    }

    onQueryChanged: launcher.recompute()

    Component.onCompleted: {
        launcher.queueRefresh()
    }
}