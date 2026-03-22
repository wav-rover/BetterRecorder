# Current app behaviors (Electron reference)

This document describes how the **Recordly-based** Electron app behaves today. It is intended as a reference for a future native macOS (SwiftUI) rewrite. All UI strings in the app are **English-only**.

Source layout for this fork: [`old-electron/`](../old-electron/).

---

## Recording flow

### Starting a recording

- The main **HUD** is a transparent window (`windowType=hud-overlay`) rendered by [`LaunchWindow`](../old-electron/src/components/launch/LaunchWindow.tsx). The user picks a **screen or window** source, optional **microphone**, **system audio**, **webcam**, and an optional **countdown** (0 / 3 / 5 / 10 seconds).
- **Source selection** can use a dedicated window (`windowType=source-selector`, [`SourceSelector`](../old-electron/src/components/launch/SourceSelector.tsx)) opened from the HUD when no source is chosen yet.
- **Countdown** (`windowType=countdown`) shows a full-screen overlay before capture starts when countdown is enabled.
- **Tray**: from the menu bar tray, the user can open the HUD or stop an active recording (IPC `stop-recording-from-tray`).

Routing is centralized in [`App.tsx`](../old-electron/src/App.tsx) via the `windowType` query parameter.

### Capture implementation

- [`useScreenRecorder`](../old-electron/src/hooks/useScreenRecorder.ts) coordinates **native screen recording** on macOS (and other platform-specific paths), optional **MediaRecorder**-based paths, **microphone** mixing, and optional **webcam** recording.
- When recording stops successfully, `finalizeRecordingSession` calls:
  - `setCurrentVideoPath(videoPath)` or `setCurrentRecordingSession({ videoPath, webcamPath })` so the editor knows which files to load.
  - **`switch-to-editor`** IPC, which closes the main HUD window and opens the **editor** window ([`handlers.ts`](../old-electron/electron/ipc/handlers.ts) `switch-to-editor` handler; window creation in [`main.ts`](../old-electron/electron/main.ts)).

### Where files go

- Default recordings directory is under app **userData**: `RECORDINGS_DIR` = `path.join(app.getPath('userData'), 'recordings')` in [`electron/main.ts`](../old-electron/electron/main.ts). The user can change the folder from the HUD “more” menu (`chooseRecordingsDirectory`).

### Opening the editor without a new recording

- **Open video** / **open project** from the HUD call preload APIs, then `switchToEditor()` so the editor window loads with the chosen file or project.

---

## Timeline and editing

### Project model

- A saved project is JSON (`.recordly`) described by [`EditorProjectData`](../old-electron/src/components/video-editor/projectPersistence.ts): version, paths to **source video** (and related assets), plus editor state.
- [`ProjectEditorState`](../old-electron/src/components/video-editor/projectPersistence.ts) holds:
  - **Zoom regions** (`zoomRegions`), **trim** (`trimRegions`), **speed** (`speedRegions`), **annotations**, **audio** ducking regions, **crop**, **webcam** overlay settings, **auto-captions**, aspect ratio, export defaults, and **cursor** presentation settings.

### Timeline UI

- [`TimelineEditor`](../old-electron/src/components/video-editor/timeline/TimelineEditor.tsx) is the multi-row timeline: zoom, trim, annotations, speed, audio, etc. It works with [`dnd-timeline`](https://www.npmjs.com/package/dnd-timeline) for drag-and-drop spans.
- [`VideoEditor`](../old-electron/src/components/video-editor/VideoEditor.tsx) hosts the **preview** ([`VideoPlayback`](../old-electron/src/components/video-editor/VideoPlayback.tsx)), timeline, and export entry points.

### Zooms and cursor

- **Zoom regions** are [`ZoomRegion`](../old-electron/src/components/video-editor/types.ts): `startMs`, `endMs`, `depth` (`ZoomDepth` 1–6), and `focus` (`ZoomFocus` normalized center).
- **Cursor** telemetry is [`CursorTelemetryPoint`](../old-electron/src/components/video-editor/types.ts) (time, position, interaction type, cursor type). Playback rendering uses helpers under [`videoPlayback/`](../old-electron/src/components/video-editor/videoPlayback/) (e.g. [`cursorRenderer.ts`](../old-electron/src/components/video-editor/videoPlayback/cursorRenderer.ts), [`cursorViewport.ts`](../old-electron/src/components/video-editor/videoPlayback/cursorViewport.ts)).
- **Suggested zooms** can be derived from cursor activity ([`zoomSuggestionUtils`](../old-electron/src/components/video-editor/timeline/zoomSuggestionUtils.ts)).

### Typical user actions

- **Trim**: define regions to remove segments (conceptually “holes” in the linear timeline; see in-app tutorial [`TutorialHelp`](../old-electron/src/components/video-editor/TutorialHelp.tsx)).
- **Move / resize** timeline items via drag handles where the row type supports it.
- **Speed**: `SpeedRegion` segments change playback speed for spans.
- **Zoom**: add or edit zoom keyframes on the zoom row; easing and connected-zoom behavior are controlled from editor state (durations, overlap, easing — see defaults in [`types.ts`](../old-electron/src/components/video-editor/types.ts) and preferences).

Keyboard shortcuts are configurable via [`ShortcutsContext`](../old-electron/src/contexts/ShortcutsContext.tsx) and [`ShortcutsConfigDialog`](../old-electron/src/components/video-editor/ShortcutsConfigDialog.tsx).

---

## Useful settings (user-facing)

Persisted editor UI defaults live in [`editorPreferences.ts`](../old-electron/src/components/video-editor/editorPreferences.ts) (localStorage key `recordly.editor.preferences`). Notable groups:

- **Canvas / framing**: wallpaper, shadow, background blur, aspect ratio, border radius, padding, **crop** region.
- **Zoom animation**: motion blur, connect zooms, zoom in/out durations, overlap, gap, easing presets.
- **Cursor**: show/hide, loop, **style** (e.g. tahoe / dot / figma / mono), size, smoothing, motion blur, click bounce, **sway**.
- **Webcam overlay**: enable, device path, position, size, mirror, corner radius, shadow, react-to-zoom.
- **Export defaults**: `exportQuality`, `exportFormat` (MP4 vs GIF), GIF frame rate, loop, size preset.

In-project state duplicates many of these fields in `ProjectEditorState` so a `.recordly` file travels with the video.

---

## Export flow

### UI

- Export is driven from the editor header and [`ExportDialog`](../old-electron/src/components/video-editor/ExportDialog.tsx), with shared option widgets in [`ExportSettingsMenu`](../old-electron/src/components/video-editor/ExportSettingsMenu.tsx).

### Formats and quality

- [`ExportFormat`](../old-electron/src/lib/exporter/types.ts): `'mp4' | 'gif'`.
- **MP4**: [`ExportQuality`](../old-electron/src/lib/exporter/types.ts) = `medium` | `good` | `high` | `source` — maps to output dimensions and bitrate in the exporter pipeline ([`videoExporter.ts`](../old-electron/src/lib/exporter/videoExporter.ts), [`frameRenderer.ts`](../old-electron/src/lib/exporter/frameRenderer.ts)).
- **GIF**: [`GifFrameRate`](../old-electron/src/lib/exporter/types.ts) (15–30 FPS), loop flag, [`GifSizePreset`](../old-electron/src/lib/exporter/types.ts) (`medium` / `large` / `original`) with max height caps in `GIF_SIZE_PRESETS`.

### Progress and result

- [`ExportProgress`](../old-electron/src/lib/exporter/types.ts) tracks frame progress, optional phases (`extracting`, `finalizing`, `saving`), and percentage.
- The user is prompted to **save** the output file (system save dialog from the main process). After export, the UI can **reveal in Finder** via `revealInFolder` (see `VideoEditor`).

---

## Electron shell

- **Application menu** ([`setupApplicationMenu`](../old-electron/electron/main.ts)): File (load/save project), Edit, View (in **development** builds: reload / devtools; in **packaged** builds: zoom and fullscreen only), Window.
- **IPC** for editor lifecycle includes `switch-to-editor`, menu channels `menu-load-project`, `menu-save-project`, `menu-save-project-as`.

This is a behavioral snapshot only; filenames and line references may shift as the codebase evolves.
