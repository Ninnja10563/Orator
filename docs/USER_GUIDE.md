# Working with Orator

Orator runs on Apple Silicon Macs with macOS 14 or later. Download the ZIP or DMG from a successful macOS workflow run. Extract the ZIP and move Orator.app to Applications, or open the DMG and drag Orator to its Applications shortcut. Current CI archives have an ad-hoc signature; they have not been notarized by Apple. The separate distribution workflow produces a notarized ZIP and DMG when the repository owner configures Developer ID credentials.

## Start a presentation

Choose **File → New**, then **Slide → Add Slide** (Command–Shift–N) to choose a layout. Use the toolbar or Insert menu to add text, shapes, images, tables, charts, connectors or media. Drag a slide thumbnail to reorder it. The navigator supports multiple selection and contextual slide commands.

Drag the dividers to resize the navigator, canvas, inspector and notes. The View menu hides panels, controls zoom, and shows rulers and guides. Command–0 fits the slide. Speaker notes belong to the selected slide and are saved with the document.

## Edit content

Click an object to select it, Shift-click to extend selection, or drag over empty canvas to select several objects. Drag selection handles to resize or rotate. Arrow keys move by one point; Shift increases the step. Option temporarily disables snapping. Arrange contains alignment, distribution, grouping, locking and layer commands.

Double-click text or a table cell to edit in place. Select characters before applying font, color, emphasis or paragraph changes. Tab and Shift–Tab adjust nesting inside a list. Clicking outside the text ends editing; saving also includes unfinished text edits. Command–Z and Command–Shift–Z undo and redo.

Double-click a group to work on its contents. Escape leaves group editing. Use the table and chart editors for structure and data. Image cropping and background removal retain the original image; **Format → Restore Original Image** restores it.

Use **Slide → Edit / Finish Editing Master** for shared artwork and **Slide → Master Typography** for inherited fonts. Save and apply custom master layouts from the Slide menu. Local overrides are retained when themes or master settings change.

## Animate and present

Open **Slide → Animation Timeline** to add, order and preview object effects. Set click/previous triggers, delay and duration. Motion paths are editable on the canvas. Slide transitions are configured in the inspector; Continuity interpolates related objects across duplicated slides.

Set video/audio trimming, volume, fades, looping and automatic playback under **Format → Media Playback Settings**. The media preview plays the embedded original asset with those settings.

Choose **Present → Present from Current Slide** (Command–Shift–P). On a second display, the audience sees the slides while the presenter sees notes and navigation. Arrow keys and Space navigate; Escape ends the presentation. B toggles black, P pauses, L toggles the laser, D enables the pen, H enables the highlighter, E erases ink, and J jumps to a slide. Rehearse Timings records time spent on each slide.

## Save, recover and exchange

Save the editable original as `.orator`. It is a macOS document package containing metadata and original assets. Treat it as one file in Finder; do not edit its internal members. Older single-file Orator documents open normally and migrate through safe saving. Asset checksums detect damaged or incomplete packages.

Autosave uses NSDocument. Independent recovery snapshots are retained separately. After an unexpected termination, recovered presentations open as labeled copies; review and save them before replacing any original.

Use **File → Import PowerPoint** and **File → Export PowerPoint** for PPTX exchange. Read the conversion report and keep the source document. Common editable content, used masters/layouts, comments, animations and media settings are exchanged, but unusual effects and third-party extensions can differ. Continuity exports as Fade. Orator comment resolution and object anchors are retained as extension metadata; other applications can show them as ordinary slide comments.

Use PDF export for fixed-layout sharing, Speaker Notes PDF for paginated notes, and File → Print for native printing. Google Slides exchange uses PPTX; Orator does not need a Google account.

## Report a problem

Include the Orator version, macOS version, Mac model, the exact action, and whether the issue survives reopening. For exchange problems, include a minimal source document and the export report if you can share them safely. Do not attach private presentation content or signing credentials to a public issue.
