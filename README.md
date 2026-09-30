# Orator

A native macOS presentation editor built with Swift and AppKit, targeting Apple Silicon and macOS 14 or later. Version **0.1.0 — foundation preview**. No web runtime, cloud account or external AI service is required.

## Build and run

Install Xcode's command-line tools on a Mac, then:

```sh
swift test
scripts/build-app.sh
open build/Orator.app
```

The build creates an arm64 application with an ad-hoc signature. Distribution signing and notarization are not configured. CI publishes a downloadable build artifact, not a production release.

## Available workflows

- Multiple native documents; versioned `.orator` files; standard save, autosave, undo and redo. Separate recovery snapshots reopen as clearly labeled copies.
- Slide layouts, sections, multi-selection in the navigator, drag reorder, duplication, deletion, skip and clipboard exchange between documents.
- Direct AppKit canvas: selection, marquee, move, resize, rotate, keyboard nudging, snapping with Option override, group/ungroup, layers, hide/lock, align and distribute.
- Inline plain-text editing, box-level typography, theme colors and explicit overrides.
- Shapes, images with retained originals, numeric non-destructive cropping, flip and fit/fill.
- Tables and six basic chart renderers with tab-separated data editing.
- Three themes, speaker notes, ruler-dragged guides, trackpad panning, pinch/percentage/selection zoom, resizable/hideable panels.
- Fullscreen presenting, next/previous, black screen, pause, laser pointer, fade/push transitions, timed advance and a separate presenter display.
- Vector PDF export; genuine zipped Office Open XML PPTX import/export with an explicit compatibility report.

## Compatibility and current limits

PPTX exports editable text, shapes, tables, pictures and speaker notes. The app flattens charts and groups to images. Imports direct slide objects and notes; master/layout inheritance, rich text runs, charts, media, animations and hyperlinks are not preserved. Keep source PPTX files. Cross-application visual fidelity is not yet certified in Microsoft PowerPoint.

Rich text, masters, animation timelines, audio/video, advanced table operations, visual crop handles, real-time collaboration and full crash-recovery fault-injection verification remain planned. Large-deck performance and accessibility require interactive macOS acceptance testing. Single-display presentation shows the audience view; presenter notes require a second display.

## Verification

The macOS workflow builds the arm64 app, runs model/geometry/OOXML/recovery tests (including a 500-slide file), launches the bundled app through its document registration, saves and reopens a native document, and exercises canvas drag/undo, inline text saving, panel visibility and presentation controls. Exported PPTX is opened independently with python-pptx. Light/dark workspace captures and the app archive are CI artifacts.

This does not replace hands-on macOS, multiple-display, VoiceOver, or Microsoft PowerPoint acceptance testing.

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
| Duplicate objects | Command–D |
| Fit slide | Command–0 |
| Present | Command–Shift–P |
| Presentation controls | Arrows, Space, B, P, L, Escape |

Architecture, the original repository audit, and the remaining milestones are in [the development plan](docs/DEVELOPMENT.md). The UI follows the supplied unslop-ui design rules: native system controls, neutral surfaces, compact spacing and no decorative effects.
