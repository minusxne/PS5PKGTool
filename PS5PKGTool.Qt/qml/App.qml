pragma Singleton
import QtQuick
import PS5PkgTool.Native

// Application state shared by every page: settings, the library view, tasks, the log, and the
// requests pages make of the main window (dialogs, toasts, navigation).
QtObject {
    id: app

    // ------------------------------------------------------------------ state

    property var hello: ({})
    property var settings: ({})
    property var renamePresets: []
    property var renameTokens: []
    property var queryHelp: ({ fields: [], categories: [], regions: [], formats: [], sortColumns: [] })
    property var buildOptions: null
    property var stats: ({})

    property string page: "games"          // games | tools | tasks | settings
    property string selectedId: ""
    readonly property var selectedRow: selectedId.length > 0 && libraryRevision >= 0 ? Library.row(selectedId) : ({})
    property int libraryRevision: 0
    property bool libraryLoaded: false

    // Library view
    property string query: ""
    property var categories: []
    property var regions: []
    property var formats: []
    property var sortKeys: ["Title:asc"]
    property string groupBy: ""
    property string viewMode: settings.viewMode || "rail"

    // Scan
    property bool scanning: false
    property int scanProcessed: 0
    property int scanTotal: 0
    property string scanPath: ""

    // Tasks
    property var tasks: []
    property var taskSummary: ({ running: 0, waiting: 0, attention: 0, finished: 0, total: 0, autoStart: true, activePercent: 0 })
    property int unseenFinished: 0

    // Tools hand-off
    property string toolsSource: ""
    property string toolsAction: ""
    property string toolsTarget: ""

    property var startup: ({})
    property bool startupHandled: false

    readonly property ListModel logModel: ListModel {}

    // ------------------------------------------------------------------ requests to the window

    signal toastRequested(var toast)
    signal confirmRequested(var options)
    signal folderRequested(var options)
    signal fileRequested(var options)
    signal saveRequested(var options)
    signal reportRequested(string title, string text)
    signal planRequested(var options)
    signal promptRequested(var options)
    signal detailsRequested(string id)
    signal menuRequested(var ids, var anchor)
    signal duplicatesRequested(var result)
    signal searchFocusRequested()
    signal logRequested()

    function toast(title, body, kind, icon, action) {
        toastRequested({ title: title, body: body || "", kind: kind || "info", icon: icon || "", action: action || null })
    }

    function showError(context, error) {
        const message = error && error.message ? error.message : String(error)
        toast(context, message, "error", "error")
        log("Error", context + ": " + message)
    }

    function confirm(options) { confirmRequested(options) }
    function pickFolder(title, callback, initial) { folderRequested({ title: title, callback: callback, initial: initial || "" }) }
    function pickFile(title, filters, callback) { fileRequested({ title: title, filters: filters || [], callback: callback }) }
    function saveFile(title, name, filters, callback) { saveRequested({ title: title, name: name, filters: filters || [], callback: callback }) }
    function prompt(options) { promptRequested(options) }

    function log(level, message) {
        logModel.append({ time: Qt.formatTime(new Date(), "hh:mm:ss"), level: level, message: message })
        if (logModel.count > 2000) logModel.remove(0, logModel.count - 2000)
    }

    // ------------------------------------------------------------------ bridge plumbing

    function call(method, params, onResult, onError) {
        return Bridge.call(method, params || {}, onResult || function () {}, onError || function (error) { showError(method, error) })
    }

    property Connections bridgeEvents: Connections {
        target: Bridge
        function onReadyChanged() { if (Bridge.ready) app.initialize() }
        function onFailed(message) { app.toast(qsTr("Engine problem"), message, "error", "error") }
        function onStderrLine(line) { app.log("Engine", line) }
        function onEvent(name, data) { app.handleEvent(name, data) }
    }

    function initialize() {
        call("app.hello", {}, function (result) {
            hello = result
            if (result.settingsWarning) toast(qsTr("Settings were reset"), result.settingsWarning, "warning", "warning")
        })
        call("library.queryHelp", {}, function (result) { queryHelp = result })
        call("tools.buildOptions", {}, function (result) { buildOptions = result })
        call("settings.get", {}, function (result) {
            applySettings(result.settings)
            renamePresets = result.renamePresets
            renameTokens = result.renameTokens
            groupBy = settings.defaultGroupBy || ""
            reloadLibrary(function () {
                handleStartup()
                if (settings.refreshOnStartup && !startupScanDone) {
                    startupScanDone = true
                    scan()
                }
            })
        })
        call("tasks.list", {}, function (result) { tasks = result.tasks; taskSummary = result.summary })
        call("log.recent", { count: 200 }, function (result) {
            for (let i = 0; i < result.lines.length; ++i) log("File", result.lines[i])
        })
    }
    property bool startupScanDone: false

    function handleStartup() {
        if (startupHandled) return
        startupHandled = true
        const demo = startup.demoLibrary || ""
        if (demo.length > 0 && (settings.libraryFolders || []).indexOf(demo) < 0)
            addFolder(demo)
        const paths = startup.openPaths || []
        for (let i = 0; i < paths.length; ++i) openPath(paths[i])
    }

    function handleEvent(name, data) {
        switch (name) {
        case "library.changed":
            reloadTimer.restart()
            break
        case "scan.started":
            scanning = true
            scanProcessed = 0
            scanTotal = 0
            break
        case "scan.progress":
            scanProcessed = data.processed
            scanTotal = data.total
            scanPath = data.path
            break
        case "scan.finished":
            scanning = false
            break
        case "tasks.changed":
            tasks = data.tasks
            taskSummary = data.summary
            break
        case "task.queued":
            toast(qsTr("Added to Tasks"), data.title, "info", "tasks")
            break
        case "task.finished":
            onTaskFinished(data)
            break
        case "settings.changed":
            applySettings(data)
            break
        case "log":
            log(data.level, data.message)
            break
        }
    }

    function onTaskFinished(data) {
        if (page !== "tasks") unseenFinished++
        if (settings.notifyOnTaskFinish === false && data.status === "Completed") return
        const ok = data.status === "Completed"
        const cancelled = data.status === "Cancelled"
        toast(ok ? qsTr("Task complete") : cancelled ? qsTr("Task cancelled") : qsTr("Task failed"),
              data.title + (ok ? "" : "\n" + data.message),
              ok ? "success" : cancelled ? "warning" : "error",
              ok ? "check-circle" : cancelled ? "warning" : "error",
              ok && data.outputPath ? { label: qsTr("Show"), run: function () { Desktop.reveal(data.outputPath) } } : null)
        if (data.openOutput && data.outputPath) Desktop.reveal(data.outputPath)
    }

    property Connections libraryEvents: Connections {
        target: Library
        function onArtChanged(id) { if (id === app.selectedId) app.libraryRevision++ }
        function onRowsChanged() { app.libraryRevision++ }
    }

    property Timer reloadTimer: Timer {
        interval: 150
        onTriggered: app.reloadLibrary()
    }

    // ------------------------------------------------------------------ settings

    function applySettings(value) {
        settings = value
        Theme.reduceMotion = !!value.reduceMotion
    }

    function setSetting(name, value, onDone) {
        const values = {}
        values[name] = value
        setSettings(values, onDone)
    }

    function setSettings(values, onDone) {
        call("settings.set", { values: values }, function (result) {
            applySettings(result.settings)
            if (onDone) onDone(result)
            if (result.rescan) scan()
        })
    }

    // ------------------------------------------------------------------ library

    function reloadLibrary(onDone) {
        call("library.list", {}, function (result) {
            Library.setRows(result.items)
            libraryLoaded = true
            scanning = result.scanning
            refreshView(onDone)
            call("library.stats", {}, function (value) { stats = value })
        })
    }

    function viewRequest() {
        return { query: query, categories: categories, regions: regions, formats: formats, sortKeys: sortKeys, groupBy: groupBy }
    }

    function refreshView(onDone) {
        call("library.view", viewRequest(), function (result) {
            Library.setView(result)
            libraryRevision++
            const ids = Library.visibleIds()
            if (ids.length > 0 && ids.indexOf(selectedId) < 0) selectedId = ids[0]
            else if (ids.length === 0) selectedId = ""
            if (onDone) onDone()
        })
    }

    property Timer viewTimer: Timer {
        interval: 180
        onTriggered: app.refreshView()
    }
    onQueryChanged: viewTimer.restart()
    onCategoriesChanged: viewTimer.restart()
    onRegionsChanged: viewTimer.restart()
    onFormatsChanged: viewTimer.restart()
    onSortKeysChanged: viewTimer.restart()
    onGroupByChanged: viewTimer.restart()

    function hasFilters() {
        return query.length > 0 || categories.length > 0 || regions.length > 0 || formats.length > 0
    }

    function clearFilters() {
        query = ""
        categories = []
        regions = []
        formats = []
    }

    function toggleValue(list, value) {
        const copy = list.slice()
        const index = copy.indexOf(value)
        if (index >= 0) copy.splice(index, 1)
        else copy.push(value)
        return copy
    }

    function applyPreset(name) {
        clearFilters()
        switch (name) {
        case "Games": categories = ["Game"]; break
        case "Updates": categories = ["Patch"]; break
        case "DLC": categories = ["DLC"]; break
        case "Dumps": formats = ["Dump Files"]; break
        case "PKG": formats = ["PKG"]; break
        case "exFAT": formats = ["exFAT"]; break
        case "FFPKG": formats = ["FFPKG"]; break
        case "FFPFSC": formats = ["FFPFSC"]; break
        case "Needs attention": query = "role:older"; break
        }
    }

    function applySavedView(view) {
        query = view.query || ""
        categories = view.categories || []
        regions = view.regions || []
        formats = view.formats || []
        groupBy = view.groupBy || ""
        sortKeys = (view.sortKeys && view.sortKeys.length > 0) ? view.sortKeys : ["Title:asc"]
    }

    function setSort(column, additive) {
        let keys = additive ? sortKeys.slice() : []
        const existing = sortKeys.findIndex(function (key) { return key.split(":")[0] === column })
        let ascending = true
        if (existing >= 0) ascending = sortKeys[existing].split(":")[1] !== "asc"
        keys = keys.filter(function (key) { return key.split(":")[0] !== column })
        keys.push(column + ":" + (ascending ? "asc" : "desc"))
        sortKeys = keys
    }

    function scan() {
        if (scanning) return
        if ((settings.libraryFolders || []).length === 0 && (settings.manualSources || []).length === 0) {
            toast(qsTr("No library folders yet"), qsTr("Add a folder that contains your dumps, packages or images."), "info", "folder-add")
            return
        }
        scanning = true
        call("library.scan", { merge: false }, function (result) {
            scanning = false
            const errors = result.errors || []
            toast(qsTr("Library refreshed"), qsTr("%1 item(s)").arg(result.count) +
                  (errors.length > 0 ? qsTr(" · %1 could not be read").arg(errors.length) : ""), errors.length > 0 ? "warning" : "success",
                  "refresh", errors.length > 0 ? { label: qsTr("Details"), run: function () { reportRequested(qsTr("Scan problems"), errors.join("\n")) } } : null)
        }, function (error) {
            scanning = false
            if (error.code !== "cancelled") showError(qsTr("Scan failed"), error)
        })
    }

    function addFolder(path) {
        if (!path) return
        call("library.addFolder", { path: path }, function (result) {
            toast(qsTr("Folder added"), qsTr("%1 · %2 item(s) found").arg(Desktop.fileName(path)).arg(result.count || 0), "success", "folder-add")
        }, function (error) { showError(qsTr("Could not add the folder"), error) })
    }

    function addSource(path, onDone) {
        call("library.addSource", { path: path }, function (result) {
            if (onDone) onDone(result)
        }, function (error) { showError(qsTr("Could not open"), error) })
    }

    /// Opens a dump folder, package or image: added to the library and selected.
    function openPath(path) {
        if (!path) return
        if (Library.contains(path)) {
            selectedId = path
            page = "games"
            return
        }
        addSource(path, function () {
            reloadLibrary(function () {
                if (Library.contains(path)) {
                    selectedId = path
                    page = "games"
                    toast(qsTr("Opened"), Desktop.fileName(path), "success", "folder")
                } else {
                    toast(qsTr("Nothing found"), qsTr("No PS5 dump, package or image was recognised at %1").arg(path), "warning", "warning")
                }
            })
        })
    }

    function openDetails(id) {
        if (!id) return
        selectedId = id
        page = "games"
        detailsRequested(id)
    }

    function openTools(source, action, target) {
        toolsSource = source || selectedId
        toolsAction = action || ""
        toolsTarget = target || ""
        page = "tools"
    }

    // ------------------------------------------------------------------ item actions

    function copy(text, what) {
        if (!text) return
        Desktop.copyText(text)
        toast(qsTr("Copied"), what ? what + ": " + text : text, "info", "copy")
    }

    function revealItem(id) {
        if (!Desktop.reveal(id)) toast(qsTr("Not found"), qsTr("The source no longer exists on disk."), "warning", "warning")
    }

    function exportCsv(ids) {
        saveFile(qsTr("Export library"), "PS5-library.csv", ["CSV files (*.csv)"], function (path) {
            call("library.exportCsv", { ids: ids || [], path: path }, function (result) {
                toast(qsTr("Exported"), qsTr("%1 item(s) to %2").arg(result.count).arg(Desktop.fileName(path)), "success", "export",
                      { label: qsTr("Show"), run: function () { Desktop.reveal(path) } })
            })
        })
    }

    function saveArtwork(ids) {
        pickFolder(qsTr("Save artwork to"), function (folder) {
            call("library.saveArtwork", { ids: ids, folder: folder }, function (result) {
                toast(qsTr("Artwork saved"), qsTr("%1 image(s)").arg(result.saved), "success", "image",
                      { label: qsTr("Open"), run: function () { Desktop.openPath(folder) } })
            })
        }, settings.outputDirectory)
    }

    function rename(ids, format, installOrder, all) {
        call("library.renamePlan", { ids: ids || [], format: format || "", installOrder: !!installOrder, all: !!all }, function (plan) {
            planRequested({
                title: installOrder ? qsTr("Rename by install order") : qsTr("Rename"),
                subtitle: qsTr("Format: %1").arg(plan.format),
                items: plan.items,
                confirmLabel: qsTr("Rename"),
                onAccept: function () {
                    call("library.renameApply", { ids: ids || [], format: plan.format, installOrder: !!installOrder, all: !!all }, function (result) {
                        toast(qsTr("Renamed"), qsTr("%1 renamed, %2 skipped").arg(result.renamed).arg(result.skipped),
                              result.renamed > 0 ? "success" : "warning", "rename")
                    })
                }
            })
        })
    }

    function move(ids, mode) {
        pickFolder(qsTr("Move into folder"), function (folder) {
            call("library.movePlan", { ids: ids, destination: folder, mode: mode }, function (plan) {
                const run = function (addToLibrary) {
                    call("library.moveEnqueue", { ids: ids, destination: folder, mode: mode, addToLibrary: addToLibrary })
                }
                const ask = function () {
                    if (plan.destinationCovered) { run(false); return }
                    confirm({
                        title: qsTr("Add the destination to the library?"),
                        text: qsTr("%1 is not in your library folders. Add it so the moved items stay listed?").arg(folder),
                        confirmLabel: qsTr("Add and move"), cancelLabel: qsTr("Just move"),
                        onAccept: function () { run(true) }, onReject: function () { run(false) }
                    })
                }
                if (!plan.confirm) { ask(); return }
                planRequested({
                    title: qsTr("Move by %1").arg(plan.modeLabel),
                    subtitle: folder,
                    items: plan.items,
                    confirmLabel: qsTr("Move"),
                    onAccept: ask
                })
            })
        }, settings.outputDirectory)
    }

    function remove(ids) {
        call("library.busy", { ids: ids }, function (result) {
            if (result.busy.length > 0) {
                toast(qsTr("In use"), qsTr("A queued or running task is using %1 of these items.").arg(result.busy.length), "warning", "warning")
                return
            }
            if (!result.managed) {
                toast(qsTr("Not removed"), qsTr("Only items inside your library folders or opened sources can be deleted."), "warning", "warning")
                return
            }
            const permanent = !!settings.permanentDelete
            const doRemove = function () {
                const results = Desktop.removePaths(ids, permanent)
                const removed = results.filter(function (r) { return r.ok }).map(function (r) { return r.path })
                const failed = results.filter(function (r) { return !r.ok })
                if (removed.length > 0) call("library.forget", { ids: removed })
                toast(permanent ? qsTr("Deleted") : qsTr("Moved to trash"),
                      qsTr("%1 item(s)").arg(removed.length) + (failed.length > 0 ? qsTr(" · %1 failed: %2").arg(failed.length).arg(failed[0].error) : ""),
                      failed.length > 0 ? "warning" : "success", "trash")
            }
            if (!permanent && settings.confirmDelete === false) { doRemove(); return }
            confirm({
                title: permanent ? qsTr("Delete permanently?") : qsTr("Move to trash?"),
                text: permanent ? qsTr("This cannot be undone.") : qsTr("You can restore them from the trash."),
                items: ids.slice(0, 15).concat(ids.length > 15 ? [qsTr("…and %1 more").arg(ids.length - 15)] : []),
                confirmLabel: permanent ? qsTr("Delete") : qsTr("Move to trash"),
                danger: true,
                onAccept: doRemove
            })
        })
    }

    function findDuplicates() {
        call("library.duplicates", {}, function (result) { duplicatesRequested(result) })
    }

    function missingBase() {
        call("library.missingBase", {}, function (result) {
            if (result.groups.length === 0) {
                toast(qsTr("All good"), qsTr("Every update has its base game in the library."), "success", "check-circle")
                return
            }
            const lines = []
            for (let i = 0; i < result.groups.length; ++i) {
                const group = result.groups[i]
                lines.push(group.titleId + "  " + group.title)
                for (let j = 0; j < group.ids.length; ++j) lines.push("    " + group.ids[j])
            }
            reportRequested(qsTr("Updates without a base game"), lines.join("\n"))
        })
    }
}
