# Real Device Validation

## Purpose

Manual validation checklist for KAN-19 on a physical iPhone.

## Prerequisites

- Xcode with a valid development signing team.
- A physical iPhone connected to the Mac and trusted for development.
- The iPhone has network access for initial URL resolution and downloads.
- The app builds with the current `IOSMusicApp` scheme.
- The YouTube extractor bridge is running and reachable from the chosen run target.
- Bridge configuration is set for the target being used:
- Simulator can use the Debug default `http://127.0.0.1:8080`.
- Real iPhone should use `YOUTUBE_EXTRACTOR_BRIDGE_DEBUG_DEVICE_HOST` with the Mac's LAN IP, for example `192.168.1.42`.
- Real iPhone can also use a full `YOUTUBE_EXTRACTOR_BRIDGE_BASE_URL` override such as `http://192.168.1.42:8080`.
- The bridge server must listen on `0.0.0.0` or on the Mac LAN IP, not only `127.0.0.1`.
- At least one valid YouTube URL that resolves in the current provider path.

## Build And Install

1. Select a physical iPhone as the run destination in Xcode.
   Expected result: the `IOSMusicApp` target is selectable for the device.
2. Build and run the app on the device.
   Expected result: the app installs, launches, and shows the tab UI without a crash.

## End-To-End V1 Checklist

1. Paste a valid YouTube URL in the input screen.
   Expected result: the app resolves a media item and navigates to the detail screen.
2. Start one audio download from the detail screen.
   Expected result: the audio item moves through queued/downloading/downloaded without a silent failure.
3. Start one video download from the detail screen.
   Expected result: the video item downloads successfully and thumbnail caching completes when available.
4. Open the Library tab.
   Expected result: both downloaded items appear in the library.
5. Confirm the audio row shows audio metadata and the video row shows recognizable artwork.
   Expected result: audio uses placeholder artwork and video prefers the cached local thumbnail.
6. Tap the audio item.
   Expected result: the audio player opens and can play the downloaded local file.
7. Tap the video item.
   Expected result: the video player opens and can play the downloaded local file.
8. Disable network on the iPhone.
   Expected result: both previously downloaded items still open and play offline.
9. Force-quit the app and relaunch it.
   Expected result: the library still shows the downloaded items after launch reconciliation.
10. Open the same audio and video items again after relaunch.
    Expected result: playback still works because files resolve from managed Application Support storage at runtime.

## Recovery And Error Handling Checks

1. Delete a managed media file from the app container using Xcode device container tools, then relaunch the app.
   Expected result: the missing downloaded item is downgraded from playable downloaded state and no longer opens as a valid offline item.
2. Delete only a cached video thumbnail file, then relaunch the app.
   Expected result: the video item remains downloadable/playable, and the library falls back to remote artwork or placeholder.
3. Try opening a library item whose managed file has been removed.
   Expected result: the app does not crash and shows an unavailable or missing-file state instead of silent failure.

## Expected Storage Behavior

- Persisted media and thumbnail paths remain relative managed-storage paths, not absolute sandbox paths.
- Runtime file URLs are reconstructed from the current Application Support base directory.
- Downloads are stored under the managed `LocalMediaStorage/items` directory.

## Known Limitations

- Runtime download wiring now uses real YouTube watch-page extraction plus the real network downloader, but some items may still fail if YouTube only exposes ciphered or unsupported streams. See `Docs/RuntimeDownloadWiring.md`.
- Real YouTube/provider behavior still depends on the current provider implementation and any external changes.
- Device validation for background audio, interruptions, and long-running transfers is outside V1 scope.
- This checklist does not cover App Store distribution or production entitlement review.
