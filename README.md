# Orator

A native macOS presentation editor built with Swift and AppKit for Apple Silicon and macOS 14 or later. **0.2.0 — development preview** — substantial editing and presentation workflows are implemented; this is not yet a production-certified replacement for PowerPoint or Keynote. No web runtime, cloud account or external AI service is required.

## Build and run

Install Xcode's command-line tools on a Mac, then:

```sh
swift test
scripts/build-app.sh
open build/Orator.app
```

The build creates an arm64 application with a Retina icon and an ad-hoc signature. Distribution signing and notarization are not configured. Downloadable app archives and visual test captures are available from successful [macOS workflow runs](https://github.com/Ninnja10563/Orator/actions/workflows/macos.yml).

## Editing

- Native multi-document workspace with resizable slide navigator, canvas, inspector and speaker notes; system light/dark appearance and fullscreen editing.
- Slide layouts, sections, multiple selection, drag reorder, duplication, deletion, skip and slide/object clipboard exchange.
- Precise AppKit canvas with marquee selection, move/resize/rotation handles, keyboard nudging, snapping with Option override, equal spacing/size guides, ruler guides, alignment and distribution.
- Nested groups with direct group editing, layers, locking, hiding and Z-order commands. Attached straight, elbow and curved connectors follow their objects.
- Inline attributed text with fonts, selection formatting, colors, highlight, paragraph settings, lists, text fitting and undo/redo.
- Shape library with fill, gradient, border pattern and shadow controls. Original image assets, visual crop handles, aspect ratios, fit/fill, flips, masks and local Vision background removal with original restoration.
- Native table editor with rows/columns, dimensions, merged cells, fills, borders, padding and alignment; direct canvas cell editing.
- Six editable chart types with multiple series, a spreadsheet data editor, chart colors, titles, legends, axes and labels.
- Themes, editable masters and custom layouts, inherited placeholders, linked typography and intentional local overrides.
- Slide/object comment threads with replies and resolve/reopen controls.

## Presenting

Fullscreen audience output and a separate presenter display with current/next slides, notes, time and navigation. Fade, Dissolve, Push, Wipe, Slide, Zoom and **Continuity** object-matching transitions work during playback. An animation timeline supports entrance, emphasis, exit, click grouping and editable motion paths.

Embedded audio/video uses AVFoundation, with preview, playback settings, trim boundaries, looping and volume. Presenter tools include black screen, pause, jump to slide, laser pointer, temporary pen/highlighter annotations and rehearsal timings.

## Documents and exchange

Versioned `.orator` documents preserve the complete native model. NSDocument supplies safe saving and autosave; independent recovery snapshots reopen as labeled copies. Reversible commands group continuous drags into one undo action.

- Vector PDF export, paginated speaker-note PDFs and native printing.
- Genuine zipped Office Open XML PPTX import/export with editable rich text, shapes, images, nested groups, connectors, tables, six chart types, embedded chart workbooks, media, notes and compatible transitions.
- PPTX import resolves master/layout appearances into editable slide content. Export reports unsupported conversions instead of silently claiming lossless compatibility.
- Google Slides exchange is through PPTX import/export; no Google account or service dependency is built into Orator.

**PPTX limits:** master/layout relationships and object animations are not retained across exchange. Continuity exports as Fade. Media playback settings, unusual shapes/effects and advanced third-party content may need adjustment. Comments are currently native-only. Keep original PPTX files. Visual fidelity has not been certified in the Microsoft PowerPoint GUI.

## Verification and remaining work

The [macOS workflow](.github/workflows/macos.yml) builds the arm64 app, runs core regression tests, launches the bundled app, exercises native editing/undo/save/presentation/media behavior, and captures light/dark workspaces and content editors. Independent python-pptx checks and Microsoft's Open XML SDK validate exported presentations and embedded chart workbooks. Tests include an independent PowerPoint fixture, theme/layout inheritance, nested groups, rich text, malformed input, recovery and a 500-slide document.

Hands-on VoiceOver, multiple-display, Vision inference and large-deck performance acceptance remain necessary. Real-time collaboration, full OOXML animation fidelity and production signing/notarization are not complete. See the [implementation status and acceptance plan](docs/DEVELOPMENT.md) for precise boundaries.

## Editing shortcuts

| Action | Control |
|---|---|
| Add slide | Command–Shift–N |
| Insert/edit text | Text toolbar / double-click |
| Select more objects | Shift-click |
| Cycle objects | Tab / Shift–Tab |
| Move precisely | Arrow keys; Shift for 10 points |
| Disable snapping for a drag | Hold Option |
| Constrain resize/rotation | Hold Shift |
| Group / ungroup | Command–Option–G / add Shift |
| Nest / unnest a list item | Tab / Shift–Tab while editing a list |
| Edit / leave a group | Double-click group / Escape |
| Duplicate objects | Command–D |
| Fit slide | Command–0 |
| Print | Command–P |
| Present | Command–Shift–P |
| Presentation navigation | Arrows, Space, J, Escape |
| Black / pause / laser | B / P / L |
| Pen / highlighter / erase | D / H / E |

UI work follows the supplied unslop-ui skill: native system controls, neutral surfaces, compact spacing and restrained feedback.
