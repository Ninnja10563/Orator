# Orator implementation and acceptance plan

## Repository audit — 1 October 2026

The original repository contained only the MIT license, one initial commit, no tags, no releases, no source, and no build or test configuration. There was no pre-existing application to preserve or run. The implementation workspace is Linux arm64 without Swift or Xcode; native verification runs on macOS CI. No production release has been certified.

## Architecture

| Area | Responsibility |
|---|---|
| PresentationCore | Codable value model, stable UUIDs, geometry, styles, tables, charts, masters, connectors, animation evaluation, reversible serializable edits, validation and OOXML adapters |
| App | AppKit NSDocument lifecycle, save/autosave, command history, independent recovery snapshots and native integration checks |
| Canvas | Mouse/key interaction, selection, transient drag previews, text editing and shared rendering |
| UI | Native menus, toolbar, split workspace, navigator, inspector, guide/master/group editing |
| Text, Images, Shapes, Tables, Charts, Media | Focused content editors and native rendering/processing/playback adapters |
| Slides | Asynchronous thumbnail scheduling and bounded caches |
| Animation, Presenter | Timeline, playback scheduling, audience/presenter windows, transitions, annotations and rehearsal |
| ImportExport | Vector slide/notes PDF, native printing and Office document exchange |
| Comments | Offline comment threads, replies and resolution |

The native format is a document package with a versioned JSON manifest, separate original asset files and SHA-256 checksums. Version 1 is migrated to version 2 on decoding; unsupported future versions are rejected. Rendering, selection and tool-window state are separate from serialized content. Continuous drags commit a single reversible command. Inline text has its own undo manager; saving includes active text before focus changes. Master and group edits resolve to their owning document commands.

Unchanged asset wrappers and hashes are reused on saving. Single-file JSON documents remain readable; native checks exercise on-disk safe migration, active-edit saving, damaged-asset rejection and original byte preservation. Individual assets are limited to 100 MB and native package assets to 2 GB; metadata is limited to 50 MB. Recovery snapshots still use the portable JSON representation and can incur significant encoding overhead for media-heavy decks.

## Implemented and covered by automated checks

- Structured slides, groups, content styles, assets, comments, masters/layouts and optional animation/media fields.
- Object selection/transforms, slide operations, geometry/snapping, nested group editing and clipboard undo.
- Attributed text persistence and selection-format undo/redo; active text serialization inside groups; visible numbered/bulleted lists, continuation and nesting.
- Rich table cell editing, active-save/undo, dimensions/merges, multi-series charts and non-destructive crop geometry.
- Master layout editing, inherited geometry/typography and local overrides.
- Animation scheduling/evaluation, Continuity matching, presenter input and pause/advance behavior.
- Real AVFoundation audio playback, pause/resume and cleanup using a generated audio fixture.
- Native document reopening, independent recovery snapshots and a 500-slide serialization regression. A separate process is forcibly killed during active editing, then a fresh process verifies recovery as a labeled independent document.
- PDF speaker-note pagination and native print-operation creation.
- PPTX fixtures from an independent producer; editable tables/charts/groups, rich cell text and hyperlinks, font units, retained used masters/layouts, inherited placeholders, attached connectors, classic comment authors/replies, object animation timing and transition settings.
- Media playback triggers, volume, looping, fades and trim exchange; native AVFoundation duration resolution translates end-trim offsets.
- Export validation with python-pptx and Microsoft's Open XML SDK, including embedded XLSX chart data.
- Native drag/draw/undo interactions in a 500-slide, 12,000-object document, with observed frame timing logged and a coarse hang guard. This is not a substitute for a hardware performance matrix.
- Native app launches and visual captures of light/dark workspaces and table/chart/crop editors.

CI artifacts provide the exact app archive and captures associated with each commit. Schema validity is evidence of structural compatibility, not a guarantee of identical rendering in PowerPoint.

## Remaining acceptance and engineering work

1. **Interactive macOS acceptance:** VoiceOver navigation and announcements, keyboard-only authoring, real trackpad interactions, multiple displays, native printing on actual printers, and foreground-removal inference on representative photographs.
2. **Scale and reliability:** measured frame/interaction latency on M1 through newer chips; stress documents with many large assets; memory-pressure tests; power-loss and mid-write fault injection. Safe-save migration and damaged-package checks are automated.
3. **Text and content depth:** physical video playback checks in rotated groups, advanced shape adjustments and additional curve controls.
4. **Interoperability:** GUI round trips against PowerPoint/Keynote and Google Slides; fixture corpus expansion; modern Office comment variants, unusual animation parameters and third-party extensions. Used master/layout relationships, classic threaded comments, common object animations and media settings are implemented. Keep explicit compatibility reporting.
5. **Collaboration:** current stable IDs, serializable operations and offline comments are foundations only. Durable revision journals, conflict semantics, presence and a synchronization transport remain unimplemented. There is no simulated collaboration UI.
6. **Distribution:** credentialed signing/notarization, update policy and installer/release acceptance. The workflow, ZIP/DMG packaging and secret setup documentation are implemented, but no credentials are configured and notarization has not run. Ad-hoc CI builds are development previews.

The project must not be described as a finished professional-suite replacement until these acceptance boundaries have been closed with evidence.
