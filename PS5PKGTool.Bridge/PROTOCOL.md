# Bridge protocol

`ps5pkgtool-bridge` is the headless engine of the Linux edition. It runs the shared C# libraries
(`PS5PKGTool.Core`, `PS5PKGTool.Ffpfsc`, `PS5PKGTool.Ufs2`) and talks to a frontend over
**JSON lines on stdin/stdout**. The Qt app starts it as a child process, but anything that can
write and read lines of JSON can drive it, which makes it handy for scripting and tests.

```sh
printf '%s\n' '{"id":1,"method":"app.hello"}' '{"id":2,"method":"app.shutdown"}' | ./ps5pkgtool-bridge
```

## Envelopes

| Direction | Shape |
|---|---|
| Request (client → bridge) | `{"id": 7, "method": "library.view", "params": {…}}` |
| Result | `{"id": 7, "result": …}` |
| Error | `{"id": 7, "error": {"code": "not_found", "message": "…", "detail": "…"}}` |
| Event (bridge → client, unsolicited) | `{"event": "tasks.changed", "data": {…}}` |

- Every request gets exactly one result or error. Requests run concurrently.
- `id` is chosen by the client; use a positive integer.
- Property names are camelCase and enums are strings.
- Error codes: `bad_request`, `not_found`, `unknown_method`, `parse_error`, `cancelled`,
  `disk_space`, `io_error`, `failed`.
- Long calls (scans, details loads, artwork, duplicates) can be stopped with
  `call.cancel {"id": <request id>}`; they then fail with `cancelled`.
- stdout carries protocol lines only. Diagnostics go to stderr and to the log file.
- Library items are identified by their source path (`id` = path of the dump folder or file).

## Methods

### App
| Method | Params | Result |
|---|---|---|
| `app.hello` | – | version, protocol, os, runtime, data/cache/log directories, `settingsWarning`, `backends[]` (id, name, available, reason), `methods[]` |
| `app.cacheInfo` | – | `artworkBytes`, `artworkText`, `directory` |
| `app.clearCaches` | – | `{ok}` |
| `app.shutdown` | – | `{ok}`; the bridge exits after answering |
| `call.cancel` | `id` | `{cancelled}` |
| `log.recent` | `count` | `{lines[]}`: the tail of the log file |

### Settings and saved views
| Method | Params | Result |
|---|---|---|
| `settings.get` | – | `settings`, `renamePresets[]`, `renameTokens[]`, `groupKeys[]` |
| `settings.set` | `values` (partial settings object) | `settings`, `rescan` (folders or recursion changed) |
| `settings.renameExample` | `format`, `id?` | `example`, `unknownTokens[]` |
| `settings.export` | `path`, `includePasscode` | `{path, includedPasscode}` |
| `settings.importPreview` | `path` | `changes[]` (human-readable) |
| `settings.importApply` | `path` | `settings` |
| `settings.reset` | – | `settings` (folders, sources and views are kept) |
| `views.save` / `views.delete` | `view` / `name` | `views[]` |

### Library
| Method | Params | Result |
|---|---|---|
| `library.list` | – | `items[]` (GameRow), `scanning`, `roots[]` |
| `library.view` | `query`, `categories[]`, `regions[]`, `formats[]`, `sortKeys[]` (`"Size:desc"`), `groupBy` | `ids[]`, `groups[]` (key, label, count, ids), `visibleCount`, `totalCount`, `warning` |
| `library.stats` | – | totals by category and format, missing, superseded, missingBase |
| `library.queryHelp` | – | search fields with examples, filter values, sort columns |
| `library.scan` | `roots?[]`, `merge` | `count`, `added`, `errors[]` |
| `library.cancelScan` | – | `{ok}` |
| `library.addFolder` / `library.removeFolder` | `path`, `scan?` | scan result / `{ok}` |
| `library.addSource` / `library.removeSource` | `path` | scan result / `{ok}` |
| `library.clear`, `library.removeMissing`, `library.forget` | – / – / `ids[]` | `{removed}` |
| `library.clearRecent`, `library.saveManifest` | – | – |
| `library.thumbnails` | `ids[]`, `full` | `items{id: {icon, background, pic0, pic1}}`: PNG paths in the cache |
| `library.duplicates` | – | `groups[]` (verdict `identical` or `possible`, copies with hash) |
| `library.missingBase` | – | `groups[]` of updates whose base game is absent |
| `library.exportCsv` | `ids[]` (empty = all), `path` | `{count}` |
| `library.saveArtwork` | `ids[]`, `folder` | `{saved, folder}` |
| `library.renamePlan` / `library.renameApply` | `ids[]` or `all`, `format?`, `installOrder` | plan `items[]` (status `rename`, `conflict`, `unchanged`, `error`) / `{renamed, skipped, failures[]}` |
| `library.movePlan` | `ids[]`, `destination`, `mode` (`title`, `titleid`, `category`, `region`, `source`, `flat`) | `items[]`, `modeLabel`, `destinationCovered`, `confirm` |
| `library.moveEnqueue` | `ids[]`, `destination`, `mode`, `addToLibrary` | `{taskId, count}` |
| `library.busy` | `ids[]` | `busy[]` (in use by a task), `managed` (all inside library folders/sources) |

A **GameRow** has: `id`, `title`, `titleId`, `contentId`, `conceptId`, `category`, `role`, `region`,
`format`, `source`, `sourceKind`, `platform`, `sizeBytes`, `sizeText`, `version`, `contentVersion`,
`masterVersion`, `targetVersion`, `firmware`, `sdk`, `drm`, `features[]`, `language`,
`creationDate`, `fileName`, `location`, `missing`, `superseded`, `missingBase`, `warningCount`,
`icon` and `background` (cached PNG paths, empty until requested).

### Details and files
| Method | Params | Result |
|---|---|---|
| `details.get` | `id` | `row`, `overview[]` (titled property groups), `artwork[]`, `sections[]`, `errors[]`, `trophies`, `activities`, `executable`, `files` (summary), `rawParam`, `localizedTitles[]` |
| `details.container` | `id` | `header[]`, `segments`, `entries`, `sfo`, `keystone`, `si`, `playGo` (summary, chunks, scenarios, files) |
| `details.ebootHash` | `id` | `{sha256}` |
| `files.list` | `id` | `note`, `totalBytes`, `files[]` (path, size, origin, encrypted) |
| `files.preview` | `id`, `path` | `kind` (`image`, `text`, `hex`, `media`), `info` (format, size, metadata), `file` or `text` |
| `files.hex` | `id`, `path`, `offset`, `length?` | `text`, `offset`, `length`, `fileSize`, `hasPrevious`, `hasNext` |
| `files.materialize` | `id`, `path`, `size?` | `{file}`: a local copy for players and "open with" |
| `files.extract` | `id`, `paths[]`, `destination` | `{taskId}` |

Tables (`stats`, `modules`, `segments`, …) are `{columns[], rows[][]}` of strings.

### Tools
| Method | Params | Result |
|---|---|---|
| `tools.inspect` | `source` | kind, kindLabel, explanation, title/IDs, size, `actions[]` (id, label, description, enabled, reason), `targets[]` (id, label, extension, description, suggested output), `extractOutput`, `canBuildPackage`, `buildBlockedReason`, `passcode` |
| `tools.buildOptions` | – | `defaultBackend`, `builders[]` (availability, note, per-builder defaults), `sdkVersions[]`, `krakenLevels[]`, `drmModes[]`, `compressionModes[]`, `tempDirectory`, `passcode` |
| `tools.diskCheck` | `source`, `output`, `temp?`, `target` | `status` (`Ok`, `NearLimit`, `Insufficient`), `message`, `free`, `volume` |
| `tools.enqueue` | `source`, `action` (`convert`, `extract`, `verify`, `repair`, `ampr`, `rebuild`), `target?` (`exfat`, `ffpkg`, `ffpfsc`, `pkg`), `output`, `overwrite`, `options` | `{taskId, output, warning?}` |
| `editor.open` | `source` (exFAT or FFPKG image) | `format`, `entries[]` (path, isDirectory, size) |
| `editor.apply` | `source`, `operations[]` (`kind`: `replace`, `addFile`, `addFolder`, `mkdir`, `delete`; `imagePath`; `sourcePath?`) | `{taskId}` |

`options` keys: exFAT `cluster` (0, 32768, 65536) and `ampr`; FFPKG `block`, `fragment`, `density`
and `minFree`; FFPFSC `level` (1–9) and `gain`; package `passcode`, `backend` (`lpp`, `ppt`),
`packageType`, `drm` (`upgradable`, `free`, `standard`, or `""` to keep the source value), `sdk`
(index into `sdkVersions`, -1 = auto), `compression` (`Auto`, `Kraken`, `Stored`), `krakenLevel`,
`krakenThreads`, `playGo`, `temp`, `deterministic`, `fakeSign` and `rightSprx`.

### Tasks
| Method | Params | Result |
|---|---|---|
| `tasks.list` | – | `tasks[]`, `summary` |
| `tasks.cancel`, `tasks.retry`, `tasks.remove` | `id` | `{ok}` |
| `tasks.cancelAll`, `tasks.clearCompleted`, `tasks.startNext` | – | counts / `{ok}` |
| `tasks.setAutoStart` | `value` | `{autoStart}` |
| `tasks.report` | `id` | `{report}`: a text diagnostic with secrets masked |

A task snapshot has `id`, `type`, `title`, `operation`, `route`, source and output paths and
names, `status`, `stage`, `stepText`, `stepPercent`, `taskPercent`, `message`, `currentFile`,
`counts`, `elapsed`, `eta`, `result`, `attempts`, `queuePosition`, timestamps, `canCancel`,
`canRetry`, `canRemove`, `outputExists`, `builder` and `restorable`.

## Events

| Event | Data |
|---|---|
| `ready` | `{version}`, sent once the manifest and task queue are loaded |
| `log` | `{time, level, message}` |
| `settings.changed` | the full settings object |
| `library.changed` | `{reason}`: refetch with `library.list` / `library.view` |
| `scan.started`, `scan.progress`, `scan.finished` | `{roots}` / `{processed, total, path}` / `{}` |
| `tasks.changed` | `{tasks[], summary}`, at most 4 times a second |
| `task.queued` | `{id, title}` |
| `task.finished` | `{id, title, status, message, outputPath, diskSpace, openOutput}` |

## Files

| What | Where |
|---|---|
| Settings, library manifest, task queue | `$XDG_DATA_HOME/PS5PKGTool/` (default `~/.local/share/PS5PKGTool/`) |
| Log | `$XDG_DATA_HOME/PS5PKGTool/logs/PS5PKGTool.log` |
| Decoded artwork and preview copies | `$XDG_CACHE_HOME/PS5PKGTool/` (default `~/.cache/PS5PKGTool/`) |

`settings.json` has the same format as the Windows edition's file, plus a few Linux-only fields.
The data directory is created with mode 0700, because `tasks.json` can hold a custom debug
passcode so that queued builds can be retried after a restart.
