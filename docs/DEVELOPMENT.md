# Orator development plan

## Repository audit — 1 October 2026

The original repository contained only the MIT license, one initial commit, no tags, no releases, no source, and no build or test configuration. There was no pre-existing functionality to preserve or run. The implementation workspace is Linux arm64 without Swift or Xcode; native verification runs in macOS CI.

## Implementation boundaries

- `PresentationCore`: Codable value model, stable UUIDs, original asset bytes, theme-linked colors, nested groups, geometry, reversible serializable edits, format validation and Office Open XML adapter. No AppKit dependency.
- `App`: AppKit document lifecycle, NSDocument safe save/autosave and standard undo registration. Native `.orator` documents are versioned JSON with embedded assets.
- `Canvas`: AppKit mouse/key events, drag previews committed once at mouse-up, selection separate from persisted state, rendering shared with output. Images and slide thumbnails are cached.
- `UI`: native menus, customizable toolbar, split workspace, slide navigator, formatting controls, data editors.
- `Presenter`: audience window, separate display console, transitions and timed advancement.
- `ImportExport`: vector PDF and bounded PPTX interoperability. Original documents are never overwritten on import.

## Next milestones, in order

1. **Reliability and accessibility:** interactive macOS QA, VoiceOver testing, inspector mixed values, large-deck background thumbnail scheduling, recovery fault injection, UI automation.
2. **Document depth:** attributed text runs, paragraph/list editing, masters and inherited placeholders, section collapsing, nested group isolation, connectors and editable guide properties.
3. **Content tools:** visual image crop mode, masks, Vision processing service, direct table cell editing and merges, full chart series/axes editor, AVFoundation audio/video.
4. **Motion and presentation:** animation data/engine/timeline, object identity interpolation (working name: Continuity), motion paths, presenter jump/rehearsal/ink tools.
5. **Interoperability:** OOXML schema validation and PowerPoint/Keynote fixture corpus; master/theme inheritance, mixed text runs, media, native charts and transition fidelity. Optional Google Slides exchange through PPTX, without a service dependency.
6. **Collaboration:** durable operation journal, revisions and conflict semantics before any network transport, comment editor/replies/presence. No collaboration UI until functional.

This is a foundation preview, not a claim of parity with Keynote or PowerPoint. Features must graduate from model support to UI and tested behavior before being described as implemented.
